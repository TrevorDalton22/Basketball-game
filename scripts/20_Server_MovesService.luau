--!strict
-- MovesService (ModuleScript) — ServerScriptService > Server > MovesService
-- Steals (defense) and crossovers (offense). The client only asks; the server
-- checks distance, facing, cooldowns and match state, rolls the steal, and
-- moves the ball. Blocks live in ShotService because they happen at release.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Server = script.Parent
local BallService = require(Server:WaitForChild("BallService"))
local CharacterService = require(Server:WaitForChild("CharacterService"))
local MatchService = require(Server:WaitForChild("MatchService"))
local RemoteGuard = require(Server:WaitForChild("RemoteGuard"))

local MovesService = {}
MovesService.ScriptVersion = 2 -- Main compares this to spot an old copy; bump when this file changes
MovesService.ScriptFile = "20_Server_MovesService" -- Main/ClientMain compare this to spot another file's code pasted here

local DEFENSE = Config.Defense
local MOVES = Config.Moves

local lastSteal: { [Player]: number } = {}
local lastCrossover: { [Player]: number } = {}
local immuneUntil: { [Player]: number } = {} -- steal-proof window after a crossover
local rng = Random.new()
local feedback: RemoteEvent
local moveSerial = 0

-- Tell every client a move happened, so each can animate it on that player
-- (a new value every time, e.g. "Reach:12"). Cosmetic only.
local MOVE_ATTRIBUTE = "StreetHoopsMove"
local function publishMove(player: Player, name: string)
	moveSerial += 1
	player:SetAttribute(MOVE_ATTRIBUTE, ("%s:%d"):format(name, moveSerial))
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function tellBoth(a: Player, b: Player?, kind: string, data: { [string]: any })
	feedback:FireClient(a, kind, data)
	if b and b.Parent then
		feedback:FireClient(b, kind, data)
	end
end

local function onSteal(player: Player)
	if not RemoteGuard.Allow(player) then
		return
	end
	local now = os.clock()
	local last = lastSteal[player]
	if last and now - last < DEFENSE.StealCooldown then
		return
	end
	local ball, opponent = MatchService.GetLiveMatch(player)
	if not ball or not opponent or ball.State ~= "Held" or ball.Holder ~= opponent then
		return -- only when your opponent has the ball in a live match
	end
	local myRoot = CharacterService.GetRoot(player)
	local theirRoot = CharacterService.GetRoot(opponent)
	-- Position is checked against the last sample right now, so teleporting
	-- onto the carrier and back between samples doesn't work
	if not myRoot or not theirRoot or not CharacterService.IsMoveLegit(player) then
		return
	end
	lastSteal[player] = now
	publishMove(player, "Reach")

	-- A miss slows you, and you can't scoop up a loose ball until you recover
	-- (the server enforces that part even if a client ignores the slow-down)
	local function penalise(slowTime: number, speed: number)
		CharacterService.Slow(player, slowTime, speed)
		ball.NoPickupUntil[player] = now + slowTime
	end
	local function miss(reason: string)
		penalise(DEFENSE.StealMissSlowTime, DEFENSE.StealMissSpeed)
		feedback:FireClient(player, "Steal", { Success = false, Reason = reason, StealerUserId = player.UserId })
	end

	local toCarrier = flat(theirRoot.Position - myRoot.Position)
	local gap = toCarrier.Magnitude
	if gap > DEFENSE.StealRange then
		miss("Too far")
		return
	end
	-- Facing only matters at arm's length; right on top of them, any reach counts
	local facing = if gap > 1e-3 then flat(myRoot.CFrame.LookVector).Unit:Dot(toCarrier.Unit) else 1
	if gap > DEFENSE.StealCloseRange and facing < DEFENSE.StealFacingDot then
		miss("Not facing them")
		return
	end

	-- Reaching into a crossover: ankles broken
	local immune = immuneUntil[opponent]
	if immune and immune > now then
		penalise(DEFENSE.AnklesSlowTime, DEFENSE.AnklesSpeed)
		publishMove(player, "Ankles")
		tellBoth(player, opponent, "Ankles", { DefenderUserId = player.UserId, HandlerUserId = opponent.UserId })
		return
	end

	-- No reaching into a shot (that is what blocks are for)
	if ball.Part:GetAttribute("Shooting") == true then
		miss("Reach-in")
		return
	end

	local closeness = 1 - math.clamp(gap / DEFENSE.StealRange, 0, 1)
	local chance = DEFENSE.StealBaseChance + DEFENSE.StealCloseBonus * closeness
	if rng:NextNumber() >= chance then
		miss("Missed")
		return
	end

	-- Poke it loose toward the defender, starting over the carrier's root (the
	-- held ball itself can hang over a line the carrier is standing inside)
	local held = ball.Part.Position
	local ballPos = Vector3.new(theirRoot.Position.X, held.Y, theirRoot.Position.Z)
	local away = flat(myRoot.Position - ballPos)
	local dir = if away.Magnitude > 1e-3 then away.Unit else flat(myRoot.CFrame.LookVector)
	local velocity = dir * DEFENSE.PokeSpeed + Vector3.new(0, 6, 0)
	if BallService.Knock(ball, ballPos, velocity, player, DEFENSE.StolenRegrabDelay) then
		tellBoth(player, opponent, "Steal", { Success = true, StealerUserId = player.UserId, VictimUserId = opponent.UserId })
	end
end

local function onCrossover(player: Player, direction: any)
	if not RemoteGuard.Allow(player) then
		return
	end
	if direction ~= 1 and direction ~= -1 then
		return
	end
	local now = os.clock()
	local last = lastCrossover[player]
	if last and now - last < MOVES.CrossoverCooldown then
		return
	end
	local ball = BallService.FindHeldBy(player)
	if not ball or ball.Part:GetAttribute("Shooting") == true then
		return
	end
	-- Only while the ball is live (or practising): not while frozen at a check
	if not MatchService.GetShotContext(ball, player) then
		return
	end
	lastCrossover[player] = now
	immuneUntil[player] = now + MOVES.CrossoverImmunity
	-- Switch hands (BallVisuals mirrors the ball to the other side)
	ball.Part:SetAttribute("Hand", if direction < 0 then "Left" else "Right")
end

function MovesService.Init()
	feedback = Net.Event("Feedback")
	Net.Event("Steal").OnServerEvent:Connect(onSteal)
	Net.Event("Crossover").OnServerEvent:Connect(onCrossover)
	Players.PlayerRemoving:Connect(function(player)
		lastSteal[player] = nil
		lastCrossover[player] = nil
		immuneUntil[player] = nil
	end)
end

return MovesService
