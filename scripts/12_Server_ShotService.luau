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

-- Where the ball should cross the rim plane.
-- Decided misses cross outside the ring's tube centreline, so contact with the
-- rim pushes the ball away from the hoop instead of rolling it in. As a
-- backstop, BallService only counts a decided miss that physically touched
-- the hoop.
local function aimPoint(rim: Vector3, toRim: Vector3, boardDir: Vector3, made: boolean, quality: string, fraction: number, distance: number): Vector3
	local side = toRim:Cross(Vector3.yAxis)
	local r = Config.Court.RimRadius
	local outside = r + Config.Court.RimTube + Config.Ball.Radius * 0.35
	-- Far enough from the ring that the ball cannot touch it at all
	local clear = r + Config.Court.RimTube + Config.Ball.Radius + 0.3
	local sideSign = if rng:NextNumber() < 0.5 then -1 else 1
	-- From the wings/baseline one "side" points into the glass; always miss away from it
	local towardBoard = side:Dot(boardDir)
	if math.abs(towardBoard) > 0.35 then
		sideSign = if towardBoard > 0 then -1 else 1
	end
	-- Shooting from beside/behind the board, the "front" of the rim is next to the glass
	local frontNearBoard = (-toRim):Dot(boardDir) > 0.3

	local function sideMiss(): Vector3
		return rim + side * (sideSign * outside) + toRim * rng:NextNumber(-0.3, 0.3)
	end
	local function frontMiss(): Vector3
		if frontNearBoard then
			return sideMiss()
		end
		return rim - toRim * outside + side * rng:NextNumber(-0.3, 0.3)
	end

	if made then
		return rim + side * rng:NextNumber(-0.12, 0.12) + toRim * rng:NextNumber(-0.12, 0.12)
	end
	if fraction < SHOT.AirballFraction then
		-- Way too early: falls short, well clear of the ring. Too close to fall
		-- short in front of the shooter? Then it falls off to the side instead.
		local room = distance - SHOT.ReleaseForward - 0.5
		if room >= clear and not frontNearBoard then
			local short = math.clamp(rng:NextNumber(2.5, 4.5), clear, room)
			local target = rim - toRim * short - Vector3.new(0, 1, 0)
			-- Keep it off the glass (the board's front face is this far behind the rim)
			local glassGap = Config.Court.RimDistance - Config.Court.BackboardZ - Config.Ball.Radius - 0.2
			if (target - rim):Dot(boardDir) < glassGap then
				return target
			end
		end
		return rim + side * (sideSign * clear) - Vector3.new(0, 1, 0)
	elseif quality == "Early" then
		return frontMiss()
	elseif quality == "Late" then
		if fraction > 1 then
			-- Very late: off the glass well wide of the ring, so it caroms away
			local wide = r + Config.Ball.Radius + rng:NextNumber(0.6, 1.4)
			return rim + side * (sideSign * wide) + toRim * 1.05 + Vector3.new(0, 1.2, 0)
		end
		-- Long: off the side of the back rim
		return rim + side * (sideSign * outside) + toRim * 0.4
	end
	-- A good release that still rims out: off the side or the front of the rim
	if rng:NextNumber() < 0.5 then
		return sideMiss()
	end
	return frontMiss()
end

local function resolveShot(player: Player, entry: Pending, clientHold: number?)
	local ball = entry.Ball
	if ball.State ~= "Held" or ball.Holder ~= player then
		return -- lost the ball before releasing
	end
	local context = MatchService.GetShotContext(ball, player)
	local root = CharacterService.GetRoot(player)
	local court = ball.Court
	local origin: CFrame = court.Origin
	local function reject(reason: string)
		ball.Part:SetAttribute("Shooting", false)
		feedback:FireClient(player, "ShotRejected", { Reason = reason })
	end
	if not context or not root then
		reject("")
		return
	end
	-- No shots from out of bounds in a match (BallService calls the turnover)
	if not context.Practice and not BasketballMath.IsInBounds(origin, root.Position, 0) then
		reject("Out of bounds")
		return
	end
	if CharacterService.IsSuspicious(player) then
		reject("")
		return
	end
	-- No shots from behind the backboard: the glass is in the way
	local localPos = origin:PointToObjectSpace(root.Position)
	local boardHalf = Config.Court.BackboardSize.X / 2 + Config.Ball.Radius + 0.5
	if localPos.Z < Config.Court.BackboardZ and math.abs(localPos.X) <= boardHalf then
		reject("No shots from behind the backboard")
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

	local rim: Vector3 = court.RimCenter
	local shooterPos = root.Position
	local distance = BasketballMath.DistanceToRim(origin, shooterPos)
	local points = BasketballMath.ShotPoints(origin, shooterPos)
	local toRim = flatUnit(rim - shooterPos, origin:VectorToWorldSpace(Vector3.new(0, 0, -1)))

	local chance = makeChance(quality, distance, shooterPos, toRim, context.Defender)
	local made = rng:NextNumber() < chance
	local boardDir = origin:VectorToWorldSpace(Vector3.new(0, 0, -1)) -- from the rim toward the backboard
	local target = aimPoint(rim, toRim, boardDir, made, quality, fraction, distance)

	local from = shooterPos + Vector3.new(0, SHOT.ReleaseHeight, 0) + toRim * SHOT.ReleaseForward
	local apexY = rim.Y + BasketballMath.ArcHeight(distance)
	local velocity = BasketballMath.SolveArc(from, target, apexY, Config.Ball.Gravity)

	local shot = {
		Id = BallService.NewShotId(),
		Shooter = player,
		Points = points,
		Quality = quality,
		MatchId = context.MatchId,
		Practice = context.Practice == true,
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
	if not ball or CharacterService.IsSuspicious(player) or not MatchService.GetShotContext(ball, player) then
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
