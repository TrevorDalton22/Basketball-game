--!strict
-- ShotService (ModuleScript) — ServerScriptService > Server > ShotService
-- Handles shot requests. For a jump shot the client only says "I started
-- holding shoot" and "I let go after N seconds"; for a layup/dunk it says
-- "finish". The server checks possession and match state, measures the hold
-- itself, picks layup vs dunk from its own view of the drive, decides make or
-- miss, and launches the ball.

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
ShotService.ScriptVersion = 4 -- Main/ClientMain compare this to spot an old copy; bump when this file changes
ShotService.ScriptFile = "12_Server_ShotService" -- and this to spot another file's code pasted here

local SHOT = Config.Shot
local DEFENSE = Config.Defense
local FINISH = Config.Finish
local MAX_HOLD_TIME = SHOT.FillTime * SHOT.MaxHoldFraction

-- Token: server-side id for the auto-release timer
-- ClientToken: the client's shot number, echoed back so it can match replies
-- DefenderGrounded: the defender was on the ground when the shot began (only
-- then can they block it: you have to react to the shot, not pogo-jump)
-- Kind: "Jumper" (resolved by ShootRelease) or "Layup"/"Dunk" (resolved on a timer)
-- PressDistance: distance to the rim when a layup/dunk was pressed
type Pending = { Ball: any, StartedAt: number, Token: number, ClientToken: number, DefenderGrounded: boolean, Kind: string, PressDistance: number, PressPosition: Vector3 }

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

-- Is this release a guaranteed basket? (checked before blocks and the make roll)
local function sureMake(quality: string): boolean
	return quality == "Perfect" and SHOT.PerfectAlwaysScores == true
end

local function makeChance(quality: string, distance: number, shooterPos: Vector3, toRim: Vector3, defender: Player?): number
	if sureMake(quality) then
		return 1
	end
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
	local frontNearBoard = (-toRim):Dot(boardDir) > 0.15

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

-- Is `defender` in the air between the shooter and the rim, close enough to block?
local function isBlocked(defender: Player, shooterPos: Vector3, toRim: Vector3, origin: CFrame, chanceScale: number?): boolean
	local root = CharacterService.GetRoot(defender)
	local humanoid = CharacterService.GetHumanoid(defender)
	if not root or not humanoid or not CharacterService.IsMoveLegit(defender) then
		return false
	end
	-- A defender still stumbling from a missed reach or broken ankles can't block
	if CharacterService.IsSlowed(defender) then
		return false
	end
	local offset = root.Position - shooterPos
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local gap = flat.Magnitude
	if gap > DEFENSE.BlockRange or gap < 1e-3 or flat.Unit:Dot(toRim) < DEFENSE.BlockFacingDot then
		return false
	end
	-- A real jump: off the ground now, and only for as long as a jump lasts
	if CharacterService.TimeSinceGrounded(defender) > DEFENSE.BlockMaxAirTime then
		return false
	end
	local standing = CharacterService.StandingHeight(humanoid, root)
	local rise = (root.Position.Y - origin.Position.Y) - standing
	if rise < DEFENSE.BlockMinRise or rise > Config.Movement.JumpHeight + 0.5 then
		return false
	end
	return rng:NextNumber() < DEFENSE.BlockChance * (chanceScale or 1)
end

-- Where shots are never allowed: out of bounds (in a match) and behind/beside the glass
local function shotSpotProblem(origin: CFrame, position: Vector3, practice: boolean): string?
	if not practice and not BasketballMath.IsInBounds(origin, position, 0) then
		return "" -- the out-of-bounds turnover message explains it
	end
	local localPos = origin:PointToObjectSpace(position)
	local boardHalf = Config.Court.BackboardSize.X / 2 + 3.5
	if localPos.Z < Config.Court.BackboardZ + 0.3 and math.abs(localPos.X) <= boardHalf then
		return "No shots from behind the backboard"
	end
	return nil
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
		-- A refused shot leaves the ball in hand: open a real steal window before
		-- the next one, so refused shots can't be chained into a steal-proof shield.
		-- RetryIn lets the client hold off instead of flashing a meter that is refused.
		lastShotAt[player] = os.clock() + DEFENSE.StealCooldown
		feedback:FireClient(player, "ShotRejected", { Reason = reason, Token = entry.ClientToken, RetryIn = DEFENSE.StealCooldown + SHOT.MinShotInterval })
	end
	if not context or not root then
		reject("")
		return
	end
	if CharacterService.IsSuspicious(player) then
		reject("")
		return
	end
	local problem = shotSpotProblem(origin, root.Position, context.Practice)
	if problem then
		reject(problem)
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

	local from = shooterPos + Vector3.new(0, SHOT.ReleaseHeight, 0) + toRim * SHOT.ReleaseForward

	-- Blocked? The defender must be airborne, close, and between shooter and rim
	-- (a Perfect release can't be blocked)
	if context.Defender and entry.DefenderGrounded and not sureMake(quality) and isBlocked(context.Defender, shooterPos, toRim, origin) then
		local side = toRim:Cross(Vector3.yAxis)
		local deflect = -toRim * rng:NextNumber(9, 15) + side * rng:NextNumber(-7, 7) + Vector3.new(0, rng:NextNumber(6, 11), 0)
		ball.Part:SetAttribute("Shooting", false)
		if BallService.Knock(ball, from, deflect, context.Defender, DEFENSE.BlockedRegrabDelay, DEFENSE.BlockerGrabDelay) then
			local data = { BlockerUserId = context.Defender.UserId, ShooterUserId = player.UserId }
			feedback:FireClient(player, "Block", data)
			feedback:FireClient(context.Defender, "Block", data)
			feedback:FireClient(player, "ShotRejected", { Reason = "", Token = entry.ClientToken })
		end
		return
	end

	local chance = makeChance(quality, distance, shooterPos, toRim, context.Defender)
	local made = chance >= 1 or rng:NextNumber() < chance
	local boardDir = origin:VectorToWorldSpace(Vector3.new(0, 0, -1)) -- from the rim toward the backboard
	local target = aimPoint(rim, toRim, boardDir, made, quality, fraction, distance)

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
		Kind = "Jumper",
	}
	if BallService.Launch(ball, from, velocity, shot) then
		feedback:FireClient(player, "Release", { Quality = quality, Fraction = fraction, Points = points, Token = entry.ClientToken })
	end
end

--------------------------------------------------------------------------------
-- Layups and dunks
--------------------------------------------------------------------------------

-- Which finish the player is in position for, judged from the server's own
-- view of their distance and real recent movement toward the rim (nil = not
-- driving). The server's copy of a running player trails the client by a
-- moment, so a little of their travel is credited to the distance.
local function finishKindFor(player: Player, origin: CFrame, rim: Vector3, root: BasePart): (string?, number)
	local distance = BasketballMath.DistanceToRim(origin, root.Position)
	local toRim = flatUnit(rim - root.Position, origin:VectorToWorldSpace(Vector3.new(0, 0, -1)))
	local approach = CharacterService.ApproachSpeed(player, toRim)
	local judged = math.max(0, distance - math.clamp(approach, 0, Config.Movement.WalkSpeed) * FINISH.LagCompensation)
	if judged <= FINISH.DunkRange and approach >= FINISH.DunkMinApproach then
		return "Dunk", distance
	elseif judged <= FINISH.LayupRange and approach >= FINISH.LayupMinApproach then
		return "Layup", distance
	end
	return nil, distance
end

local function finishChance(kind: string, shooterPos: Vector3, toRim: Vector3, defender: Player?): number
	local chance = if kind == "Dunk" then FINISH.DunkMakeChance else FINISH.LayupMakeChance
	if defender then
		local defenderRoot = CharacterService.GetRoot(defender)
		if defenderRoot then
			local offset = defenderRoot.Position - shooterPos
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local gap = flat.Magnitude
			if gap < SHOT.ContestRadius and gap > 1e-3 and flat.Unit:Dot(toRim) > 0.2 then
				local closeness = 1 - gap / SHOT.ContestRadius
				chance *= 1 - SHOT.ContestMaxPenalty * FINISH.ContestScale * closeness
			end
		end
	end
	return math.clamp(chance, 0.01, 0.99)
end

-- Keep a court-local point out in front of the glass
local function inFrontOfGlass(origin: CFrame, point: Vector3, margin: number): Vector3
	local localPoint = origin:PointToObjectSpace(point)
	local minZ = Config.Court.BackboardZ + margin
	if localPoint.Z < minZ then
		return origin:PointToWorldSpace(Vector3.new(localPoint.X, localPoint.Y, minZ))
	end
	return point
end

local function resolveFinish(player: Player, entry: Pending)
	local ball = entry.Ball
	if ball.State ~= "Held" or ball.Holder ~= player then
		return -- stripped before the finish
	end
	local context = MatchService.GetShotContext(ball, player)
	local root = CharacterService.GetRoot(player)
	local court = ball.Court
	local origin: CFrame = court.Origin
	local function reject(reason: string, lockout: boolean)
		ball.Part:SetAttribute("Shooting", false)
		ball.Part:SetAttribute("Finish", "")
		-- Same steal window as a refused jump shot (see resolveShot)
		if lockout then
			lastShotAt[player] = os.clock() + DEFENSE.StealCooldown
		end
		local retryIn = if lockout then DEFENSE.StealCooldown + SHOT.MinShotInterval else 0
		feedback:FireClient(player, "ShotRejected", { Reason = reason, Token = entry.ClientToken, RetryIn = retryIn })
	end
	if not context or not root or not CharacterService.IsMoveLegit(player) then
		reject("", true)
		return
	end
	-- The spot was checked at the press; a baseline drive may drift under the
	-- glass during the windup, so only the bounds are checked again here
	if not context.Practice and not BasketballMath.IsInBounds(origin, root.Position, 0) then
		reject("", false)
		return
	end

	local kind = entry.Kind
	local rim: Vector3 = court.RimCenter
	local shooterPos = root.Position
	local distance = BasketballMath.DistanceToRim(origin, shooterPos)
	-- Did they actually get there? Backing off (or never arriving) doesn't dunk.
	if distance > entry.PressDistance + 1 or distance > FINISH.LayupRange then
		-- Past the rim (beyond it from where they pressed), or never got there
		local pressToRim = rim - entry.PressPosition
		local rimToNow = shooterPos - rim
		local crossed = Vector3.new(pressToRim.X, 0, pressToRim.Z):Dot(Vector3.new(rimToNow.X, 0, rimToNow.Z)) > 0
		reject(if crossed then "Ran past the rim" else "Couldn't get to the rim", true)
		return
	end
	if kind == "Dunk" and distance > FINISH.DunkStopShort + FINISH.DunkArriveSlack then
		kind = "Layup" -- stopped short (body-blocked): it becomes a layup from where they are
	end

	local toRim = flatUnit(rim - shooterPos, origin:VectorToWorldSpace(Vector3.new(0, 0, -1)))
	local side = toRim:Cross(Vector3.yAxis)
	local boardDir = origin:VectorToWorldSpace(Vector3.new(0, 0, -1)) -- from the rim toward the glass
	local points = if kind == "Dunk" then Config.Scoring.Dunk else Config.Scoring.Layup
	ball.Part:SetAttribute("Finish", "")

	-- Blocked? Same rules as a jump shot, but dunks are much harder to stop
	local blockScale = if kind == "Dunk" then FINISH.DunkBlockFactor else 1
	if context.Defender and entry.DefenderGrounded and isBlocked(context.Defender, shooterPos, toRim, origin, blockScale) then
		local from = inFrontOfGlass(origin, shooterPos + Vector3.new(0, SHOT.ReleaseHeight, 0) + toRim * SHOT.ReleaseForward, Config.Ball.Radius + 0.3)
		local deflect = -toRim * rng:NextNumber(9, 15) + side * rng:NextNumber(-7, 7) + Vector3.new(0, rng:NextNumber(6, 11), 0)
		ball.Part:SetAttribute("Shooting", false)
		if BallService.Knock(ball, from, deflect, context.Defender, DEFENSE.BlockedRegrabDelay, DEFENSE.BlockerGrabDelay) then
			local data = { BlockerUserId = context.Defender.UserId, ShooterUserId = player.UserId, Kind = kind }
			feedback:FireClient(player, "Block", data)
			feedback:FireClient(context.Defender, "Block", data)
		end
		return
	end

	local made = rng:NextNumber() < finishChance(kind, shooterPos, toRim, context.Defender)
	local from: Vector3
	local velocity: Vector3
	if kind == "Dunk" then
		if made then
			-- Slammed straight down through the ring
			from = rim + Vector3.new(0, 1.4, 0) - toRim * 0.2
			velocity = Vector3.new(0, -32, 0) + toRim * 1.5
		else
			-- Clanged off the front of the rim; bounced off the glass side if the
			-- dunker came in from the baseline
			local out = -toRim
			local into = out:Dot(boardDir)
			if into > 0 then
				out = (out - boardDir * (2 * into)).Unit
			end
			from = rim + Vector3.new(0, 1.3, 0) + out * (Config.Court.RimRadius + Config.Ball.Radius + 0.3)
			velocity = out * rng:NextNumber(8, 12) + side * rng:NextNumber(-5, 5) + Vector3.new(0, rng:NextNumber(9, 13), 0)
		end
	else
		-- Released close to the rim (not from wherever the jump happens to be),
		-- above rim height, and always in front of the glass
		local back = math.max(distance - 1.2, Config.Court.RimRadius + Config.Court.RimTube + Config.Ball.Radius + 0.2)
		local lift = math.clamp(shooterPos.Y + SHOT.ReleaseHeight + 0.6 - rim.Y, 1.0, FINISH.LayupArc - 0.5)
		from = inFrontOfGlass(origin, rim - toRim * back + Vector3.new(0, lift, 0), 1.0)
		local target = aimPoint(rim, toRim, boardDir, made, "Good", SHOT.IdealFraction, distance)
		velocity = BasketballMath.SolveArc(from, target, rim.Y + FINISH.LayupArc, Config.Ball.Gravity)
	end

	local shot = {
		Id = BallService.NewShotId(),
		Shooter = player,
		Points = points,
		Quality = kind,
		MatchId = context.MatchId,
		Practice = context.Practice == true,
		Made = made,
		Kind = kind,
	}
	if BallService.Launch(ball, from, velocity, shot) and kind == "Dunk" and not made then
		-- A clank off the front rim counts as a rim touch (resets the shot clock)
		ball.TouchedRim = true
	end
end

local function onFinish(player: Player, clientToken: any, clientKind: any)
	if not RemoteGuard.Allow(player) then
		return
	end
	local shotNumber: number = if RemoteGuard.IsNumber(clientToken, 0, 1e9) then clientToken else 0
	local function refuse(reason: string?, retryIn: number?)
		feedback:FireClient(player, "ShotRejected", { Reason = reason or "", Token = shotNumber, RetryIn = retryIn })
	end
	if pending[player] then
		refuse()
		return
	end
	local now = os.clock()
	local last = lastShotAt[player]
	if last and now - last < SHOT.MinShotInterval then
		refuse(nil, last + SHOT.MinShotInterval - now)
		return
	end
	local ball = BallService.FindHeldBy(player)
	local context = ball and MatchService.GetShotContext(ball, player)
	local root = CharacterService.GetRoot(player)
	if not ball or not context or not root or not CharacterService.IsMoveLegit(player) then
		refuse()
		return
	end
	local court = ball.Court
	local problem = shotSpotProblem(court.Origin, root.Position, context.Practice)
	if problem then
		refuse(problem)
		return
	end
	local kind, pressDistance = finishKindFor(player, court.Origin, court.RimCenter, root)
	if not kind then
		refuse("Too far out or too slow to finish") -- not actually driving at the rim
		return
	end
	-- The client already played its move: never upgrade it, only downgrade
	if kind == "Dunk" and clientKind == "Layup" then
		kind = "Layup"
	end

	local defender = context.Defender
	local defenderGrounded = defender ~= nil and CharacterService.WasGroundedWithin(defender, FINISH.DefenderGroundedAtPress)
	tokenCounter += 1
	local token = tokenCounter
	local entry: Pending = {
		Ball = ball,
		StartedAt = now,
		Token = token,
		ClientToken = shotNumber,
		DefenderGrounded = defenderGrounded,
		Kind = kind,
		PressDistance = pressDistance,
		PressPosition = root.Position,
	}
	pending[player] = entry
	lastShotAt[player] = now
	ball.Part:SetAttribute("Shooting", true)
	ball.Part:SetAttribute("Finish", kind)
	feedback:FireClient(player, "Finish", { Kind = kind, Token = shotNumber })
	if defender and defender.Parent then
		feedback:FireClient(defender, "Finish", { Kind = kind, Token = 0 })
	end

	task.delay(if kind == "Dunk" then FINISH.DunkTime else FINISH.LayupTime, function()
		if pending[player] == entry then
			pending[player] = nil
			resolveFinish(player, entry)
		end
	end)
end

local function onShootStart(player: Player, clientToken: any)
	if not RemoteGuard.Allow(player) then
		return
	end
	local shotNumber: number = if RemoteGuard.IsNumber(clientToken, 0, 1e9) then clientToken else 0
	local function refuse(reason: string?, retryIn: number?)
		-- Tell the client so its meter does not show a shot that never happened
		-- (and, during a wait, how long to hold off)
		feedback:FireClient(player, "ShotRejected", { Reason = reason or "", Token = shotNumber, RetryIn = retryIn })
	end
	if pending[player] then
		refuse()
		return
	end
	local now = os.clock()
	local last = lastShotAt[player]
	if last and now - last < SHOT.MinShotInterval then
		refuse(nil, last + SHOT.MinShotInterval - now)
		return
	end
	local ball = BallService.FindHeldBy(player)
	local context = ball and MatchService.GetShotContext(ball, player)
	local root = CharacterService.GetRoot(player)
	if not ball or not context or not root or CharacterService.IsSuspicious(player) then
		refuse()
		return
	end
	-- Check the spot now too, so the "shooting" flag can't be raised from a
	-- spot where the shot will be refused anyway
	local problem = shotSpotProblem(ball.Court.Origin, root.Position, context.Practice)
	if problem then
		refuse(problem)
		return
	end
	local defender = context.Defender
	local defenderGrounded = defender ~= nil and CharacterService.WasGroundedWithin(defender, DEFENSE.DefenderGroundedAtShot)
	tokenCounter += 1
	local token = tokenCounter
	pending[player] = { Ball = ball, StartedAt = now, Token = token, ClientToken = shotNumber, DefenderGrounded = defenderGrounded, Kind = "Jumper", PressDistance = 0, PressPosition = root.Position }
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
	if not entry or entry.Kind ~= "Jumper" then
		return -- nothing held (a layup/dunk resolves on its own timer)
	end
	pending[player] = nil
	local clientHold: number? = if RemoteGuard.IsNumber(holdTime, 0, 10) then holdTime else nil
	resolveShot(player, entry, clientHold)
end

function ShotService.Init()
	feedback = Net.Event("Feedback")
	Net.Event("ShootStart").OnServerEvent:Connect(onShootStart)
	Net.Event("ShootRelease").OnServerEvent:Connect(onShootRelease)
	Net.Event("Finish").OnServerEvent:Connect(onFinish)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastShotAt[player] = nil
	end)
end

return ShotService
