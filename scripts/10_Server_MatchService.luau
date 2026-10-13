--!strict
-- MatchService (ModuleScript) — ServerScriptService > Server > MatchService
-- One state machine per court. Owns scores, the game clock, the shot clock,
-- check-ball resets, forfeits and results. When a court has no match its ball
-- is a practice ball.
--
--   Idle ──StartMatch──► Countdown ──► Live ◄──► Dead ─► Check ─┘
--                                       │
--                                       └──► GameOver ──► Idle
--
-- Match state is published as attributes on the court Model so every client
-- (including late joiners) can read it without extra remote traffic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local BasketballMath = require(Shared:WaitForChild("BasketballMath"))

local Server = script.Parent
local BallService = require(Server:WaitForChild("BallService"))
local CharacterService = require(Server:WaitForChild("CharacterService"))
local RemoteGuard = require(Server:WaitForChild("RemoteGuard"))

local MatchService = {}

export type Side = "Home" | "Away"
export type MatchState = "Idle" | "Countdown" | "Live" | "Dead" | "Check" | "GameOver"

export type MatchResult = {
	CourtId: string,
	MatchId: number,
	Winner: Player?,
	Loser: Player?,
	HomeUserId: number,
	AwayUserId: number,
	HomeScore: number,
	AwayScore: number,
	Reason: string, -- "Score" | "Time" | "Overtime" | "Forfeit" | "Draw" | "Cancelled"
}

export type CourtState = {
	Court: any, -- CourtBuilder.CourtHandle
	Ball: any, -- BallService.Ball
	State: MatchState,
	PhaseEndsAt: number,
	MatchId: number,
	Home: Player?,
	Away: Player?,
	Scores: { Home: number, Away: number },
	Offense: Player?,
	ClockRemaining: number,
	ClockEndsAt: number,
	Overtime: boolean,
	OvertimeEndsAt: number,
	Possessor: Player?, -- who the shot clock is running against
	ShotClockEndsAt: number, -- 0 while not running
	WaitingSince: number, -- Dead state: when we started waiting for a respawn (0 = not waiting)
	-- A reset during a live shot: the turnover waits until the shot lands
	PendingTurnover: boolean,
	PendingOffense: Player?,
	PendingResetter: Player?,
	Resets: { [Player]: number },
	AwardedShots: { [number]: boolean },
	Message: string,
	WinnerUserId: number,
	ResultReason: string,
}

-- Fires (result: MatchResult) when a match ends. Progression hooks in here (Phase 5).
MatchService.MatchEnded = Signal.new()

local MATCH = Config.Match
local COURT = Config.Court

local courtStates: { CourtState } = {}
local stateByCourtId: { [string]: CourtState } = {}
local playerCourt: { [Player]: CourtState } = {}
local nextMatchId = 0
local sweepTimer = 0
local feedback: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function sideOf(cs: CourtState, player: Player?): Side?
	if player == nil then
		return nil
	elseif cs.Home == player then
		return "Home"
	elseif cs.Away == player then
		return "Away"
	end
	return nil
end

local function opponentOf(cs: CourtState, player: Player?): Player?
	local side = sideOf(cs, player)
	if side == "Home" then
		return cs.Away
	elseif side == "Away" then
		return cs.Home
	end
	return nil
end

local function participants(cs: CourtState): { Player }
	local list = {}
	if cs.Home then
		table.insert(list, cs.Home)
	end
	if cs.Away then
		table.insert(list, cs.Away)
	end
	return list
end

local function tell(cs: CourtState, kind: string, data: { [string]: any })
	for _, player in participants(cs) do
		if player.Parent then
			feedback:FireClient(player, kind, data)
		end
	end
end

local function updateSign(cs: CourtState)
	local name = cs.Court.DisplayName
	local text
	if cs.State == "Idle" then
		text = name .. " · OPEN\nStand on a pad to play 1v1"
	else
		local homeName = if cs.Home then cs.Home.DisplayName else "—"
		local awayName = if cs.Away then cs.Away.DisplayName else "—"
		local tag = if cs.State == "GameOver" then "FINAL" else "LIVE"
		text = ("%s · %s\n%s  %d – %d  %s"):format(name, tag, homeName, cs.Scores.Home, cs.Scores.Away, awayName)
	end
	if cs.Court.SignLabel.Text ~= text then
		cs.Court.SignLabel.Text = text
	end
end

-- Only write attributes that changed, so clients get no redundant updates
local function setAttr(model: Instance, name: string, value: any)
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

-- Push every client-visible value to the court Model's attributes.
-- Message is written before State so a client reacting to the State change
-- already sees the new message.
local function publish(cs: CourtState)
	local model: Model = cs.Court.Model
	setAttr(model, "Message", cs.Message)
	setAttr(model, "MatchId", cs.MatchId)
	setAttr(model, "HomeUserId", if cs.Home then cs.Home.UserId else 0)
	setAttr(model, "AwayUserId", if cs.Away then cs.Away.UserId else 0)
	setAttr(model, "HomeName", if cs.Home then cs.Home.DisplayName else "")
	setAttr(model, "AwayName", if cs.Away then cs.Away.DisplayName else "")
	setAttr(model, "HomeScore", cs.Scores.Home)
	setAttr(model, "AwayScore", cs.Scores.Away)
	setAttr(model, "TargetScore", MATCH.TargetScore)
	setAttr(model, "ClockEndsAt", cs.ClockEndsAt)
	setAttr(model, "ClockRemaining", cs.ClockRemaining)
	setAttr(model, "ShotClockEndsAt", cs.ShotClockEndsAt)
	setAttr(model, "PhaseEndsAt", cs.PhaseEndsAt)
	setAttr(model, "Overtime", cs.Overtime)
	setAttr(model, "WinnerUserId", cs.WinnerUserId)
	setAttr(model, "ResultReason", cs.ResultReason)
	setAttr(model, "State", cs.State)
	updateSign(cs)
end

--------------------------------------------------------------------------------
-- Practice mode (court has no match)
--------------------------------------------------------------------------------

local function enterPractice(cs: CourtState)
	local ball = cs.Ball
	BallService.PlaceAt(ball, cs.Court.RackPosition, "Loose")
	ball.EnforceBounds = false
	ball.LooseTimeout = Config.Ball.PracticeIdleReset
	ball.PickupFilter = function(player: Player): boolean
		return playerCourt[player] == nil
	end
end

local function updatePractice(cs: CourtState)
	local ball = cs.Ball
	local origin: CFrame = cs.Court.Origin
	if ball.State == "Scored" and os.clock() - ball.StateSince > Config.Ball.ScoredSettleTime then
		BallService.SetState(ball, "Loose")
	elseif ball.State == "Held" and ball.Holder then
		local holder: Player = ball.Holder
		local root = CharacterService.GetRoot(holder)
		local hogging = os.clock() - ball.StateSince > Config.Ball.PracticeHoldLimit
		if hogging or (root and not BasketballMath.IsInBounds(origin, root.Position, COURT.Runoff)) then
			-- Practice balls stay on the court, and nobody may sit on one
			BallService.PlaceAt(ball, cs.Court.RackPosition, "Loose")
			if hogging then
				ball.NoPickupUntil[holder] = os.clock() + Config.Ball.PracticeHogCooldown
				feedback:FireClient(holder, "Notice", { Text = "Practice ball returned so others get a turn" })
			end
		end
	elseif ball.State == "Loose" or ball.State == "Dead" then
		local position = ball.Part.Position
		if not BasketballMath.IsInBounds(origin, position, COURT.Runoff + 2) and position.Y < origin.Position.Y + 3 then
			BallService.PlaceAt(ball, cs.Court.RackPosition, "Loose")
		elseif ball.State == "Dead" then
			BallService.SetState(ball, "Loose")
		end
	end
end

--------------------------------------------------------------------------------
-- Match flow
--------------------------------------------------------------------------------

local function spotCFrame(cs: CourtState, spot: Vector3, lookAt: Vector3): CFrame
	local origin: CFrame = cs.Court.Origin
	local height = 3.2 -- HumanoidRootPart height above the floor
	local p = origin:PointToWorldSpace(Vector3.new(spot.X, height, spot.Z))
	local l = origin:PointToWorldSpace(Vector3.new(lookAt.X, height, lookAt.Z))
	return CFrame.lookAt(p, l)
end

local function pauseClock(cs: CourtState)
	if cs.ClockEndsAt > 0 then
		cs.ClockRemaining = math.max(0, cs.ClockEndsAt - now())
		cs.ClockEndsAt = 0
	end
end

local function participantFilter(cs: CourtState): (Player) -> boolean
	return function(player: Player): boolean
		return player == cs.Home or player == cs.Away
	end
end

local function bothAlive(cs: CourtState): boolean
	for _, player in participants(cs) do
		if not CharacterService.IsAlive(player) then
			return false
		end
	end
	return true
end

-- Put both players on their check spots, frozen, ball in the offense's hands
local function setupPossession(cs: CourtState, offense: Player)
	local defense = opponentOf(cs, offense)
	local hoopFloor = Vector3.new(0, 0, COURT.RimDistance)
	-- Unfreeze first: teleporting an anchored character works, but this keeps
	-- the order simple (move, then pin in place)
	CharacterService.SetFrozen(offense, false)
	CharacterService.Teleport(offense, spotCFrame(cs, COURT.OffenseSpot, hoopFloor))
	CharacterService.SetFrozen(offense, true)
	if defense then
		CharacterService.SetFrozen(defense, false)
		CharacterService.Teleport(defense, spotCFrame(cs, COURT.DefenseSpot, COURT.OffenseSpot))
		CharacterService.SetFrozen(defense, true)
	end
	local ball = cs.Ball
	ball.PickupFilter = nil
	ball.EnforceBounds = false
	BallService.SetState(ball, "Dead")
	if not BallService.GiveTo(ball, offense) then
		BallService.PlaceAt(ball, cs.Court.RackPosition, "Dead")
	end
	cs.Offense = offense
	cs.Possessor = offense
end

local function goLive(cs: CourtState)
	for _, player in participants(cs) do
		CharacterService.SetFrozen(player, false)
	end
	cs.State = "Live"
	cs.Message = ""
	cs.PhaseEndsAt = 0
	local t = now()
	if not cs.Overtime then
		cs.ClockEndsAt = t + cs.ClockRemaining
	end
	cs.ShotClockEndsAt = t + MATCH.ShotClock
	local ball = cs.Ball
	ball.PickupFilter = participantFilter(cs)
	ball.EnforceBounds = MATCH.OutOfBounds
	ball.LooseTimeout = Config.Ball.LooseTimeout
	-- If the check-ball hand-off failed, let either player grab it
	if ball.State == "Dead" then
		BallService.SetState(ball, "Loose")
		cs.Possessor = nil
	end
	publish(cs)
end

local function endMatch(cs: CourtState, winner: Player?, reason: string)
	if cs.State == "Idle" or cs.State == "GameOver" then
		return
	end
	pauseClock(cs)
	cs.State = "GameOver"
	cs.PhaseEndsAt = now() + MATCH.GameOverTime
	cs.ShotClockEndsAt = 0
	cs.WaitingSince = 0
	cs.PendingTurnover = false
	cs.PendingOffense = nil
	cs.PendingResetter = nil
	cs.WinnerUserId = if winner then winner.UserId else 0
	cs.ResultReason = reason
	cs.Message = ""
	local ball = cs.Ball
	ball.PickupFilter = nil
	ball.EnforceBounds = false
	BallService.SetState(ball, "Dead")
	-- Freeze the players still on the court. Anyone in mid-air (a game-winning
	-- dunk) is frozen once they land, not left hanging at the rim
	local matchId = cs.MatchId
	for _, player in participants(cs) do
		if CharacterService.IsAlive(player) then
			if CharacterService.WasGroundedWithin(player, 0.1) then
				CharacterService.SetFrozen(player, true)
			else
				task.spawn(function()
					local deadline = os.clock() + 1.5
					repeat
						task.wait(0.1)
					until os.clock() >= deadline or CharacterService.WasGroundedWithin(player, 0.1)
					local stillOver = (cs.State :: string) == "GameOver" and cs.MatchId == matchId
					if stillOver and table.find(participants(cs), player) and CharacterService.IsAlive(player) then
						CharacterService.SetFrozen(player, true)
					end
				end)
			end
		end
	end
	publish(cs)

	local result: MatchResult = {
		CourtId = cs.Court.Id,
		MatchId = cs.MatchId,
		Winner = winner,
		Loser = if winner then opponentOf(cs, winner) else nil,
		HomeUserId = if cs.Home then cs.Home.UserId else 0,
		AwayUserId = if cs.Away then cs.Away.UserId else 0,
		HomeScore = cs.Scores.Home,
		AwayScore = cs.Scores.Away,
		Reason = reason,
	}
	tell(cs, "MatchEnded", {
		WinnerUserId = cs.WinnerUserId,
		HomeScore = cs.Scores.Home,
		AwayScore = cs.Scores.Away,
		Reason = reason,
	})
	MatchService.MatchEnded:Fire(result)
end

-- Clock hit zero: decide the game or go to overtime
local function endByTime(cs: CourtState)
	if cs.Scores.Home ~= cs.Scores.Away then
		local winner = if cs.Scores.Home > cs.Scores.Away then cs.Home else cs.Away
		endMatch(cs, winner, "Time")
		return
	end
	-- Tied at the buzzer: next basket wins
	cs.Overtime = true
	cs.OvertimeEndsAt = now() + MATCH.OvertimeLimit
	cs.ClockRemaining = 0
	cs.ClockEndsAt = 0
	cs.Message = "OVERTIME · Next basket wins"
	tell(cs, "Overtime", {})
	publish(cs)
end

-- Stop play (after a score, turnover, reset or death). Ends the game instead if
-- the clock ran out in the same moment.
local function deadBall(cs: CourtState, nextOffense: Player?, message: string)
	pauseClock(cs)
	cs.PendingTurnover = false
	cs.PendingOffense = nil
	cs.PendingResetter = nil
	cs.Message = message
	if not cs.Overtime and cs.ClockRemaining <= 0 then
		endByTime(cs)
		if cs.State == "GameOver" then
			return
		end
	end
	cs.State = "Dead"
	cs.PhaseEndsAt = now() + MATCH.DeadBallTime
	cs.ShotClockEndsAt = 0
	cs.WaitingSince = 0
	cs.Offense = nextOffense or cs.Offense
	local ball = cs.Ball
	ball.PickupFilter = nil
	ball.EnforceBounds = false
	if ball.State ~= "Scored" then
		BallService.SetState(ball, "Dead")
	end
	publish(cs)
end

-- Return players to the lobby and reopen the court
local function finish(cs: CourtState)
	for _, side in { "Home", "Away" } do
		local player: Player? = if side == "Home" then cs.Home else cs.Away
		if player then
			playerCourt[player] = nil
			CharacterService.SetFrozen(player, false)
			CharacterService.SetInMatch(player, false)
			if player.Parent then
				local root = CharacterService.GetRoot(player)
				-- Only move players who are still near the court (not a fresh respawn)
				if root and BasketballMath.IsInBounds(cs.Court.Origin, root.Position, COURT.Runoff + 4) then
					CharacterService.Teleport(player, cs.Court.ReturnSpots[side])
				end
			end
		end
	end
	cs.State = "Idle"
	cs.Home = nil
	cs.Away = nil
	cs.Offense = nil
	cs.Possessor = nil
	cs.Scores = { Home = 0, Away = 0 }
	cs.ClockRemaining = MATCH.Duration
	cs.ClockEndsAt = 0
	cs.ShotClockEndsAt = 0
	cs.PhaseEndsAt = 0
	cs.WaitingSince = 0
	cs.PendingTurnover = false
	cs.PendingOffense = nil
	cs.PendingResetter = nil
	cs.Resets = {}
	cs.Overtime = false
	cs.OvertimeEndsAt = 0
	cs.AwardedShots = {}
	cs.Message = ""
	cs.WinnerUserId = 0
	cs.ResultReason = ""
	enterPractice(cs)
	publish(cs)
end

-- A participant left the game or chose to leave the match
local function onParticipantLeft(player: Player)
	local cs = playerCourt[player]
	if not cs or cs.State == "GameOver" or cs.State == "Idle" then
		return
	end
	local other = opponentOf(cs, player)
	if cs.State == "Countdown" or not other or not other.Parent then
		endMatch(cs, nil, "Cancelled")
	else
		endMatch(cs, other, "Forfeit")
	end
end

-- A participant's character died (reset, fell, flung). Not a forfeit: the
-- ball goes to the opponent and play waits for the respawn. Resetting over and
-- over to stall the match forfeits it.
local function onParticipantDied(player: Player)
	local cs = playerCourt[player]
	if not cs then
		return
	end
	local state = cs.State
	if state == "Idle" or state == "GameOver" then
		return
	end
	local resets = (cs.Resets[player] or 0) + 1
	cs.Resets[player] = resets
	if resets > MATCH.MaxResets then
		local other = opponentOf(cs, player)
		if other and other.Parent then
			endMatch(cs, other, "Forfeit")
		else
			endMatch(cs, nil, "Cancelled")
		end
		return
	end
	if state == "Live" then
		local ball = cs.Ball
		local shot = ball.Shot
		if ball.State == "InFlight" and shot ~= nil and shot.MatchId == cs.MatchId then
			-- Let the shot in the air land first: a reset must never cancel a
			-- basket. The turnover (and its message) waits until it misses.
			cs.PendingTurnover = true
			cs.PendingOffense = opponentOf(cs, player)
			cs.PendingResetter = player
			return
		end
		tell(cs, "Turnover", { Reason = "Player reset", LastTouchUserId = player.UserId })
		deadBall(cs, opponentOf(cs, player), "RESET · TURNOVER")
	elseif state == "Countdown" or state == "Check" then
		deadBall(cs, cs.Offense, "WAITING FOR PLAYER")
	end
end

--------------------------------------------------------------------------------
-- Ball events
--------------------------------------------------------------------------------

local function courtStateForBall(ball: any): CourtState?
	return stateByCourtId[ball.Court.Id]
end

local function onScored(ball: any, shot: any)
	local cs = courtStateForBall(ball)
	if not cs then
		return
	end
	if cs.State == "Idle" then
		if shot.Practice and shot.Shooter.Parent then
			feedback:FireClient(shot.Shooter, "Score", { ShooterUserId = shot.Shooter.UserId, Points = shot.Points, Practice = true, Kind = shot.Kind })
		end
		return
	end
	-- Only shots taken during this match, by a participant, count — and only once
	if cs.State ~= "Live" or shot.Practice or shot.MatchId ~= cs.MatchId then
		return
	end
	if cs.AwardedShots[shot.Id] then
		return
	end
	local side = sideOf(cs, shot.Shooter)
	if not side then
		return
	end
	cs.AwardedShots[shot.Id] = true
	cs.Scores[side] += shot.Points
	tell(cs, "Score", {
		ShooterUserId = shot.Shooter.UserId,
		Points = shot.Points,
		HomeScore = cs.Scores.Home,
		AwayScore = cs.Scores.Away,
		Practice = false,
		Kind = shot.Kind,
	})

	if cs.Scores[side] >= MATCH.TargetScore then
		endMatch(cs, shot.Shooter, "Score")
	elseif cs.Overtime then
		endMatch(cs, shot.Shooter, "Overtime")
	else
		-- deadBall also settles a buzzer-beater that landed after the clock ran out
		local nextOffense = if MATCH.MakeItTakeIt then shot.Shooter else opponentOf(cs, shot.Shooter)
		deadBall(cs, nextOffense, ("+%d  %s"):format(shot.Points, shot.Shooter.DisplayName))
	end
end

local function onOutOfBounds(ball: any, lastTouch: Player?, reason: string)
	local cs = courtStateForBall(ball)
	if not cs or cs.State ~= "Live" then
		return
	end
	local nextOffense = opponentOf(cs, lastTouch) or cs.Offense
	tell(cs, "Turnover", { Reason = reason, LastTouchUserId = if lastTouch then lastTouch.UserId else 0 })
	deadBall(cs, nextOffense, reason:upper())
end

local function onLost(ball: any)
	local cs = courtStateForBall(ball)
	if not cs then
		return
	end
	if cs.State == "Idle" then
		BallService.PlaceAt(ball, cs.Court.RackPosition, "Loose")
	elseif cs.State == "Live" then
		local nextOffense = opponentOf(cs, ball.LastTouch) or cs.Offense
		deadBall(cs, nextOffense, "BALL RESET")
	else
		BallService.PlaceAt(ball, cs.Court.RackPosition, "Dead")
	end
end

local function onPickedUp(ball: any, player: Player)
	local cs = courtStateForBall(ball)
	if not cs or cs.State ~= "Live" then
		return
	end
	-- A new possession restarts the shot clock, and so does a shot that hit the
	-- rim. Re-grabbing your own airball (or a glass-only miss) does not.
	if cs.Possessor ~= player or ball.TouchedRim then
		cs.Possessor = player
		cs.ShotClockEndsAt = now() + MATCH.ShotClock
		publish(cs)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function MatchService.Init(courts: { any })
	feedback = Net.Event("Feedback")
	for _, court in courts do
		local cs: CourtState = {
			Court = court,
			Ball = BallService.Create(court),
			State = "Idle",
			PhaseEndsAt = 0,
			MatchId = 0,
			Home = nil,
			Away = nil,
			Scores = { Home = 0, Away = 0 },
			Offense = nil,
			ClockRemaining = MATCH.Duration,
			ClockEndsAt = 0,
			Overtime = false,
			OvertimeEndsAt = 0,
			Possessor = nil,
			ShotClockEndsAt = 0,
			WaitingSince = 0,
			PendingTurnover = false,
			PendingOffense = nil,
			PendingResetter = nil,
			Resets = {},
			AwardedShots = {},
			Message = "",
			WinnerUserId = 0,
			ResultReason = "",
		}
		table.insert(courtStates, cs)
		stateByCourtId[court.Id] = cs
		enterPractice(cs)
		publish(cs)
	end

	BallService.Scored:Connect(onScored)
	BallService.OutOfBounds:Connect(onOutOfBounds)
	BallService.Lost:Connect(onLost)
	BallService.PickedUp:Connect(onPickedUp)

	-- A departed player stays referenced by their court until finish() clears it
	Players.PlayerRemoving:Connect(onParticipantLeft)
	CharacterService.Died:Connect(onParticipantDied)
	Net.Event("LeaveMatch").OnServerEvent:Connect(function(player)
		if RemoteGuard.Allow(player) then
			onParticipantLeft(player)
		end
	end)
end

function MatchService.GetCourtStates(): { CourtState }
	return courtStates
end

function MatchService.IsInMatch(player: Player): boolean
	return playerCourt[player] ~= nil
end

function MatchService.StartMatch(cs: CourtState, home: Player, away: Player): boolean
	if cs.State ~= "Idle" or home == away then
		return false
	end
	if playerCourt[home] or playerCourt[away] then
		return false
	end
	if not CharacterService.IsAlive(home) or not CharacterService.IsAlive(away) then
		return false
	end
	nextMatchId += 1
	cs.MatchId = nextMatchId
	cs.Home = home
	cs.Away = away
	playerCourt[home] = cs
	playerCourt[away] = cs
	CharacterService.SetInMatch(home, true)
	CharacterService.SetInMatch(away, true)
	cs.Scores = { Home = 0, Away = 0 }
	cs.ClockRemaining = MATCH.Duration
	cs.ClockEndsAt = 0
	cs.ShotClockEndsAt = 0
	cs.WaitingSince = 0
	cs.PendingTurnover = false
	cs.PendingOffense = nil
	cs.PendingResetter = nil
	cs.Resets = {}
	cs.Overtime = false
	cs.OvertimeEndsAt = 0
	cs.AwardedShots = {}
	cs.WinnerUserId = 0
	cs.ResultReason = ""
	cs.Message = ""

	-- Kick any practice player off the ball before the tip
	local ball = cs.Ball
	ball.PickupFilter = nil
	BallService.PlaceAt(ball, cs.Court.RackPosition, "Dead")

	local first = if Random.new():NextInteger(0, 1) == 0 then home else away
	setupPossession(cs, first)
	cs.State = "Countdown"
	cs.PhaseEndsAt = now() + MATCH.CountdownTime
	publish(cs)
	tell(cs, "MatchStarting", { CourtId = cs.Court.Id })
	return true
end

-- If `player` is in a Live match: that court's ball and their opponent
function MatchService.GetLiveMatch(player: Player): (any?, Player?)
	local cs = playerCourt[player]
	if not cs or cs.State ~= "Live" then
		return nil, nil
	end
	return cs.Ball, opponentOf(cs, player)
end

-- Can `player` shoot `ball` right now? Returns context for ShotService or nil.
function MatchService.GetShotContext(ball: any, player: Player): { MatchId: number?, Practice: boolean, Defender: Player? }?
	local cs = courtStateForBall(ball)
	if not cs then
		return nil
	end
	if cs.State == "Idle" then
		if playerCourt[player] then
			return nil
		end
		return { MatchId = nil, Practice = true, Defender = nil }
	end
	if cs.State == "Live" and sideOf(cs, player) then
		return { MatchId = cs.MatchId, Practice = false, Defender = opponentOf(cs, player) }
	end
	return nil
end

local function sweepIntruders(cs: CourtState)
	local origin: CFrame = cs.Court.Origin
	for _, player in Players:GetPlayers() do
		if player == cs.Home or player == cs.Away then
			continue
		end
		local root = CharacterService.GetRoot(player)
		if root and BasketballMath.IsInBounds(origin, root.Position, COURT.Runoff) and root.Position.Y < origin.Position.Y + 20 then
			CharacterService.Teleport(player, cs.Court.ReturnSpots.Home * CFrame.new(0, 0, 4))
			feedback:FireClient(player, "Notice", { Text = "That court is in a match — queue on a pad to play" })
		end
	end
end

-- Overtime cannot last forever (checked in every active phase)
local function overtimeExpired(cs: CourtState, t: number): boolean
	if cs.Overtime and cs.OvertimeEndsAt > 0 and t >= cs.OvertimeEndsAt and (cs.Ball.State :: string) ~= "InFlight" then
		endMatch(cs, nil, "Draw")
		return true
	end
	return false
end

local function updateLive(cs: CourtState, t: number)
	local ball = cs.Ball
	-- Game clock (a shot already in the air when it expires still counts)
	if not cs.Overtime and cs.ClockEndsAt > 0 and t >= cs.ClockEndsAt then
		local shot = ball.Shot
		local buzzerBeater = ball.State == "InFlight" and shot ~= nil and shot.MatchId == cs.MatchId
		if not buzzerBeater then
			pauseClock(cs)
			endByTime(cs)
			if cs.State ~= "Live" then
				return
			end
		end
	end
	-- A reset happened while a shot was in the air; it has landed now
	if cs.PendingTurnover and (ball.State :: string) ~= "InFlight" then
		local resetter = cs.PendingResetter
		tell(cs, "Turnover", { Reason = "Player reset", LastTouchUserId = if resetter then resetter.UserId else 0 })
		deadBall(cs, cs.PendingOffense, "RESET · TURNOVER")
		return
	end
	-- Shot clock: only expires while someone is holding the ball
	if cs.ShotClockEndsAt > 0 and t >= cs.ShotClockEndsAt and (ball.State :: string) == "Held" then
		local holder = ball.Holder
		tell(cs, "Turnover", { Reason = "Shot clock", LastTouchUserId = if holder then holder.UserId else 0 })
		deadBall(cs, opponentOf(cs, holder), "SHOT CLOCK")
	end
end

local function updateDead(cs: CourtState, t: number)
	if t < cs.PhaseEndsAt then
		return
	end
	if not bothAlive(cs) then
		-- Someone is respawning; give them a fair window, then it's a forfeit
		if cs.WaitingSince == 0 then
			cs.WaitingSince = t
			cs.Message = "WAITING FOR PLAYER"
			publish(cs)
		elseif t - cs.WaitingSince > MATCH.RespawnWait then
			for _, player in participants(cs) do
				if not CharacterService.IsAlive(player) then
					local other = opponentOf(cs, player)
					endMatch(cs, other, "Forfeit")
					return
				end
			end
		end
		return
	end
	local offense = cs.Offense
	if not offense or not offense.Parent or not sideOf(cs, offense) then
		offense = cs.Home
	end
	if offense then
		setupPossession(cs, offense)
	end
	cs.State = "Check"
	cs.Message = ""
	cs.WaitingSince = 0
	cs.PhaseEndsAt = t + MATCH.CheckTime
	publish(cs)
end

function MatchService.Update(dt: number)
	local t = now()
	sweepTimer += dt
	local doSweep = sweepTimer >= 0.5
	if doSweep then
		sweepTimer = 0
	end

	for _, cs in courtStates do
		local state = cs.State
		if state == "Idle" then
			updatePractice(cs)
		elseif state ~= "GameOver" and overtimeExpired(cs, t) then
			-- ended as a draw
		elseif state == "Countdown" or state == "Check" then
			if t >= cs.PhaseEndsAt then
				goLive(cs)
			end
		elseif state == "Live" then
			updateLive(cs, t)
		elseif state == "Dead" then
			updateDead(cs, t)
		elseif state == "GameOver" then
			if t >= cs.PhaseEndsAt then
				finish(cs)
			end
		end

		if doSweep and cs.State ~= "Idle" then
			sweepIntruders(cs)
		end
	end
end

return MatchService
