--!strict
-- ShotService (ModuleScript) — ServerScriptService > Server > ShotService
-- Handles shot requests. The client only says "I started holding shoot" and
-- "I let go after N seconds". The server checks possession and match state,
-- measures the hold itself, decides make or miss, and launches the ball.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local BasketballMath = require(Shared:WaitForChild("BasketballMath"))

local Server = script.Parent
local BallService = require(Server:WaitForChild("BallService"))
local CharacterService = require(Server:WaitForChild("CharacterService"))
local MatchService = require(Server:WaitForChild("MatchService"))
local RemoteGuard = require(Server:WaitForChild("RemoteGuard"))

local ShotService = {}

local SHOT = Config.Shot
local MAX_HOLD_TIME = SHOT.FillTime * SHOT.MaxHoldFraction

type Pending = { Ball: any, StartedAt: number, Token: number }

local pending: { [Player]: Pending } = {}
local lastShotAt: { [Player]: number } = {}
local tokenCounter = 0
local rng = Random.new()

local feedback: RemoteEvent

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-3 then
		return fallback
	end
	return flat.Unit
end

local function makeChance(quality: string, distance: number, shooterPos: Vector3, toRim: Vector3, defender: Player?): number
	local chances = SHOT.MakeChance
	local chance = if quality == "Perfect" then chances.Perfect elseif quality == "Good" then chances.Good else chances.Bad
	if quality == "Good" and distance <= SHOT.CloseRange then
		chance += SHOT.CloseBonus
	end
	if distance > SHOT.DeepRange then
		local t = math.clamp((distance - SHOT.DeepRange) / (SHOT.MaxRange - SHOT.DeepRange), 0, 1)
		chance *= 1 + (SHOT.DeepRangeFloor - 1) * t
	end
	if defender then
		local defenderRoot = CharacterService.GetRoot(defender)
		if defenderRoot then
			local offset = defenderRoot.Position - shooterPos
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local gap = flat.Magnitude
			-- Only a defender between the shooter and the rim contests the shot
			if gap < SHOT.ContestRadius and gap > 1e-3 and flat.Unit:Dot(toRim) > 0.2 then
				local closeness = 1 - gap / SHOT.ContestRadius
				chance *= 1 - SHOT.ContestMaxPenalty * closeness
			end
		end
	end
	return math.clamp(chance, 0.01, 0.99)
end

-- Where the ball should cross the rim plane
local function aimPoint(rim: Vector3, toRim: Vector3, made: boolean, quality: string, fraction: number): Vector3
	local side = toRim:Cross(Vector3.yAxis)
	local r = Config.Court.RimRadius
	if made then
		local jitter = side * rng:NextNumber(-0.12, 0.12) + toRim * rng:NextNumber(-0.12, 0.12)
		return rim + jitter
	end
	if fraction < SHOT.AirballFraction then
		-- Way too early: falls well short
		return rim - toRim * rng:NextNumber(2.5, 4.5) - Vector3.new(0, 1, 0)
	elseif quality == "Early" then
		return rim - toRim * (r * 0.95) + side * rng:NextNumber(-0.4, 0.4)
	elseif quality == "Late" then
		if fraction > 1 then
			-- Very late: off the backboard
			return rim + toRim * (r + 0.6) + Vector3.new(0, 1.2, 0) + side * rng:NextNumber(-0.6, 0.6)
		end
		return rim + toRim * (r * 1.0) + side * rng:NextNumber(-0.4, 0.4)
	end
	-- A good release that still rims out somewhere around the ring
	local angle = rng:NextNumber(0, math.pi * 2)
	return rim + (toRim * math.cos(angle) + side * math.sin(angle)) * (r * 0.98)
end

local function resolveShot(player: Player, entry: Pending, clientHold: number?)
	local ball = entry.Ball
	if ball.State ~= "Held" or ball.Holder ~= player then
		return -- lost the ball before releasing
	end
	local context = MatchService.GetShotContext(ball, player)
	local root = CharacterService.GetRoot(player)
	if not context or not root then
		ball.Part:SetAttribute("Shooting", false)
		return
	end

	-- The server's own measurement is the authority; the client's value only
	-- refines it within a small tolerance to smooth out network jitter.
	local serverHold = os.clock() - entry.StartedAt
	local hold = serverHold
	if clientHold then
		hold = math.clamp(clientHold, serverHold - SHOT.ClientTimeTolerance, serverHold + SHOT.ClientTimeTolerance)
	end
	hold = math.clamp(hold, 0, MAX_HOLD_TIME)
	local fraction = hold / SHOT.FillTime
	local quality = BasketballMath.ClassifyRelease(fraction)

	local court = ball.Court
	local origin: CFrame = court.Origin
	local rim: Vector3 = court.RimCenter
	local shooterPos = root.Position
	local distance = BasketballMath.DistanceToRim(origin, shooterPos)
	local points = BasketballMath.ShotPoints(origin, shooterPos)
	local toRim = flatUnit(rim - shooterPos, origin:VectorToWorldSpace(Vector3.new(0, 0, -1)))

	local chance = makeChance(quality, distance, shooterPos, toRim, context.Defender)
	local made = rng:NextNumber() < chance
	local target = aimPoint(rim, toRim, made, quality, fraction)

	local from = shooterPos + Vector3.new(0, SHOT.ReleaseHeight, 0) + toRim * SHOT.ReleaseForward
	local apexY = rim.Y + BasketballMath.ArcHeight(distance)
	local velocity = BasketballMath.SolveArc(from, target, apexY, Config.Ball.Gravity)

	local shot = {
		Id = BallService.NewShotId(),
		Shooter = player,
		Points = points,
		Quality = quality,
		MatchId = context.MatchId,
		Practice = context.Practice,
		Made = made,
	}
	if BallService.Launch(ball, from, velocity, shot) then
		feedback:FireClient(player, "Release", { Quality = quality, Fraction = fraction, Points = points })
	end
end

local function onShootStart(player: Player)
	if not RemoteGuard.Allow(player) or pending[player] then
		return
	end
	local now = os.clock()
	local last = lastShotAt[player]
	if last and now - last < SHOT.MinShotInterval then
		return
	end
	local ball = BallService.FindHeldBy(player)
	if not ball or not MatchService.GetShotContext(ball, player) then
		return
	end
	tokenCounter += 1
	local token = tokenCounter
	pending[player] = { Ball = ball, StartedAt = now, Token = token }
	lastShotAt[player] = now
	ball.Part:SetAttribute("Shooting", true)

	-- If the release never arrives (lag, exploit, closed client) shoot it late
	task.delay(MAX_HOLD_TIME + SHOT.ClientTimeTolerance + 0.15, function()
		local entry = pending[player]
		if entry and entry.Token == token then
			pending[player] = nil
			resolveShot(player, entry, nil)
		end
	end)
end

local function onShootRelease(player: Player, holdTime: any)
	if not RemoteGuard.Allow(player) then
		return
	end
	local entry = pending[player]
	if not entry then
		return
	end
	pending[player] = nil
	local clientHold: number? = if RemoteGuard.IsNumber(holdTime, 0, 10) then holdTime else nil
	resolveShot(player, entry, clientHold)
end

function ShotService.Init()
	feedback = Net.Event("Feedback")
	Net.Event("ShootStart").OnServerEvent:Connect(onShootStart)
	Net.Event("ShootRelease").OnServerEvent:Connect(onShootRelease)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastShotAt[player] = nil
	end)
end

return ShotService
