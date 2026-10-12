--!strict
-- MatchService (ModuleScript) — ServerScriptService > Server > MatchService
-- One state machine per court. Owns scores, the game clock, check-ball resets,
-- forfeits and results. When a court has no match its ball is a practice ball.
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
	Reason: string, -- "Score" | "Time" | "Overtime" | "Forfeit" | "Cancelled"
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
	cs.Court.SignLabel.Text = text
end

-- Only write attributes that changed, so clients get no redundant updates
local function setAttr(model: Instance, name: string, value: any)
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

-- Push every client-visible value to the court Model's attributes
local function publish(cs: CourtState)
	local model: Model = cs.Court.Model
	setAttr(model, "State", cs.State)
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
	setAttr(model, "PhaseEndsAt", cs.PhaseEndsAt)
	setAttr(model, "Overtime", cs.Overtime)
	setAttr(model, "Message", cs.Message)
	setAttr(model, "WinnerUserId", cs.WinnerUserId)
	setAttr(model, "ResultReason", cs.ResultReason)
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
		-- Practice balls stay on the court
		local root = CharacterService.GetRoot(ball.Holder)
		if root and not BasketballMath.IsInBounds(origin, root.Position, COURT.Runoff) then
			BallService.PlaceAt(ball, cs.Court.RackPosition, "Loose")
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

-- Put both players on their check spots, frozen, ball in the offense's hands
local function setupPossession(cs: CourtState, offense: Player)
	local defense = opponentOf(cs, offense)
	local hoopFloor = Vector3.new(0, 0, COURT.RimDistance)
	CharacterService.Teleport(offense, spotCFrame(cs, COURT.OffenseSpot, hoopFloor))
	CharacterService.SetFrozen(offense, true)
	if defense then
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
end

local function goLive(cs: CourtState)
	for _, player in participants(cs) do
		CharacterService.SetFrozen(player, false)
	end
	cs.State = "Live"
	cs.Message = ""
	cs.PhaseEndsAt = 0
	if not cs.Overtime then
		cs.ClockEndsAt = now() + cs.ClockRemaining
	end
	local ball = cs.Ball
	ball.PickupFilter = participantFilter(cs)
	ball.EnforceBounds = MATCH.OutOfBounds
	ball.LooseTimeout = Config.Ball.LooseTimeout
	-- If the check-ball hand-off failed, let either player grab it
	if ball.State == "Dead" then
		BallService.SetState(ball, "Loose")
	end
	publish(cs)
end

local function deadBall(cs: CourtState, nextOffense: Player?, message: string)
	pauseClock(cs)
	cs.State = "Dead"
	cs.Message = message
	cs.PhaseEndsAt = now() + MATCH.DeadBallTime
	cs.Offense = nextOffense or cs.Offense
	local ball = cs.Ball
	ball.PickupFilter = nil
	ball.EnforceBounds = false
	if ball.State ~= "Scored" then
		BallService.SetState(ball, "Dead")
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
	cs.WinnerUserId = if winner then winner.UserId else 0
	cs.ResultReason = reason
	cs.Message = ""
	local ball = cs.Ball
	ball.PickupFilter = nil
	ball.EnforceBounds = false
	BallService.SetState(ball, "Dead")
	for _, player in participants(cs) do
		CharacterService.SetFrozen(player, true)
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

-- Return players to the lobby and reopen the court
local function finish(cs: CourtState)
	for _, side in { "Home", "Away" } do
		local player: Player? = if side == "Home" then cs.Home else cs.Away
		if player then
			playerCourt[player] = nil
			if player.Parent then
				CharacterService.SetFrozen(player, false)
				CharacterService.Teleport(player, cs.Court.ReturnSpots[side])
			end
		end
	end
	cs.State = "Idle"
	cs.Home = nil
	cs.Away = nil
	cs.Offense = nil
	cs.Scores = { Home = 0, Away = 0 }
	cs.ClockRemaining = MATCH.Duration
	cs.ClockEndsAt = 0
	cs.PhaseEndsAt = 0
	cs.Overtime = false
	cs.AwardedShots = {}
	cs.Message = ""
	cs.WinnerUserId = 0
	cs.ResultReason = ""
	enterPractice(cs)
	publish(cs)
end

local function endByTime(cs: CourtState)
	if cs.Scores.Home ~= cs.Scores.Away then
		local winner = if cs.Scores.Home > cs.Scores.Away then cs.Home else cs.Away
		endMatch(cs, winner, "Time")
		return
	end
	-- Tied at the buzzer: next basket wins
	cs.Overtime = true
	cs.ClockRemaining = 0
	cs.ClockEndsAt = 0
	cs.Message = "OVERTIME · Next basket wins"
	tell(cs, "Overtime", {})
	publish(cs)
end

local function onParticipantGone(player: Player, reason: string)
	local cs = playerCourt[player]
	if not cs then
		return
	end
	if cs.State == "GameOver" or cs.State == "Idle" then
		return
	end
	if cs.State == "Countdown" then
		endMatch(cs, nil, "Cancelled")
		return
	end
	local other = opponentOf(cs, player)
	if other and other.Parent then
		endMatch(cs, other, reason)
	else
		endMatch(cs, nil, "Cancelled")
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
			feedback:FireClient(shot.Shooter, "Score", { ShooterUserId = shot.Shooter.UserId, Points = shot.Points, Practice = true })
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
	})

	if cs.Scores[side] >= MATCH.TargetScore then
		endMatch(cs, shot.Shooter, "Score")
	elseif cs.Overtime then
		endMatch(cs, shot.Shooter, "Overtime")
	elseif cs.ClockEndsAt > 0 and cs.ClockEndsAt - now() <= 0 then
		-- Buzzer beater landed after the clock ran out
		pauseClock(cs)
		endByTime(cs)
		if cs.State == "Live" then
			deadBall(cs, opponentOf(cs, shot.Shooter), "OVERTIME · Next basket wins")
		end
	else
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

	-- A departed player stays referenced by their court until finish() clears it
	Players.PlayerRemoving:Connect(function(player)
		onParticipantGone(player, "Forfeit")
	end)
	CharacterService.Died:Connect(function(player)
		if MATCH.ForfeitOnDeath then
			onParticipantGone(player, "Forfeit")
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
	cs.Scores = { Home = 0, Away = 0 }
	cs.ClockRemaining = MATCH.Duration
	cs.ClockEndsAt = 0
	cs.Overtime = false
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
		elseif state == "Countdown" then
			if t >= cs.PhaseEndsAt then
				goLive(cs)
			end
		elseif state == "Live" then
			if not cs.Overtime and cs.ClockEndsAt > 0 and t >= cs.ClockEndsAt then
				local ball = cs.Ball
				local shot = ball.Shot
				local buzzerBeater = ball.State == "InFlight" and shot ~= nil and shot.MatchId == cs.MatchId
				if not buzzerBeater then
					pauseClock(cs)
					endByTime(cs)
				end
			end
		elseif state == "Dead" then
			if t >= cs.PhaseEndsAt then
				local offense = cs.Offense
				if offense and offense.Parent and (offense == cs.Home or offense == cs.Away) then
					setupPossession(cs, offense)
				end
				cs.State = "Check"
				cs.PhaseEndsAt = t + MATCH.CheckTime
				publish(cs)
			end
		elseif state == "Check" then
			if t >= cs.PhaseEndsAt then
				goLive(cs)
			end
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
