--!strict
-- BallService (ModuleScript) — ServerScriptService > Server > BallService
-- Owns every basketball: possession, loose-ball physics, pickups, shot flight
-- and basket detection. The server is the only authority on who holds a ball.
--
-- Ball states:
--   Held     welded to the holder's HumanoidRootPart
--   Loose    free physics, can be picked up by players the court allows
--   InFlight a released shot; can score; not grabbable until it comes down
--   Scored   went through the hoop; waiting for the match/practice to reset it
--   Dead     free physics, nobody can pick it up (out of bounds, pauses)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))
local BasketballMath = require(Shared:WaitForChild("BasketballMath"))

local CharacterService = require(script.Parent:WaitForChild("CharacterService"))

local BallService = {}

export type BallState = "Held" | "Loose" | "InFlight" | "Scored" | "Dead"

export type ShotRecord = {
	Id: number,
	Shooter: Player,
	Points: number,
	Quality: string,
	MatchId: number?, -- nil for practice shots
	Practice: boolean,
	Made: boolean, -- decided by ShotService at release; never sent to clients
	Kind: string, -- "Jumper" | "Layup" | "Dunk"
}

export type Ball = {
	Court: any, -- CourtBuilder.CourtHandle
	Part: Part,
	AntiGravity: VectorForce,
	Weld: Weld?,
	State: BallState,
	StateSince: number,
	Holder: Player?,
	LastTouch: Player?,
	Shot: ShotRecord?,
	LastPosition: Vector3,
	NoPickupUntil: { [Player]: number },
	-- Set by MatchService: who may pick the ball up right now (nil = nobody)
	PickupFilter: ((Player) -> boolean)?,
	-- Set by MatchService: whether out-of-bounds rules apply
	EnforceBounds: boolean,
	-- Set by MatchService: seconds a loose ball may sit untouched before Lost fires
	LooseTimeout: number,
	-- True once the ball touched the rim/backboard since the last shot. A decided
	-- miss only counts if it physically bounced in, and a rim touch resets the
	-- shot clock (like real basketball).
	TouchedHoop: boolean,
	-- Same, but the ring itself (a glass-only touch does not reset the shot clock)
	TouchedRim: boolean,
}

-- (ball, player)
BallService.PickedUp = Signal.new()
-- (ball, shot)
BallService.Scored = Signal.new()
-- (ball, lastTouch: Player?, reason: string)
BallService.OutOfBounds = Signal.new()
-- (ball) loose ball untouched for too long, or fell out of the world
BallService.Lost = Signal.new()

local balls: { Ball } = {}
local nextShotId = 0

local BALL = Config.Ball

local function setState(ball: Ball, state: BallState)
	if state ~= "InFlight" then
		-- Only a live, already-decided make may ignore the rim
		ball.Part.CollisionGroup = CharacterService.BALL_GROUP
	end
	ball.State = state
	ball.StateSince = os.clock()
	ball.Part:SetAttribute("State", state)
end

local function setHolder(ball: Ball, player: Player?)
	ball.Holder = player
	ball.Part:SetAttribute("HolderUserId", if player then player.UserId else 0)
	ball.Part:SetAttribute("Shooting", false)
	-- Which hand the ball is in (crossovers switch it; client visuals mirror it)
	ball.Part:SetAttribute("Hand", "Right")
	ball.Part:SetAttribute("Finish", "") -- "Layup"/"Dunk" while one is under way
end

local function updateAntiGravity(ball: Ball)
	-- The ball's own mass (seams are massless). Read from the part, not the
	-- assembly, so a just-broken weld can never make this the character's mass.
	local mass = ball.Part:GetMass()
	ball.AntiGravity.Force = Vector3.new(0, mass * (workspace.Gravity - BALL.Gravity), 0)
end

-- Detach from any holder and hand physics to the server
local function freePhysics(ball: Ball)
	if ball.Weld then
		ball.Weld:Destroy()
		ball.Weld = nil
	end
	local part = ball.Part
	part.Massless = false
	part.CanCollide = true
	updateAntiGravity(ball)
	ball.AntiGravity.Enabled = true
	local ok, err = pcall(function()
		part:SetNetworkOwner(nil)
	end)
	if not ok then
		warn("[BallService] SetNetworkOwner failed: " .. tostring(err))
	end
end

local function createBallPart(court: any): (Part, VectorForce)
	local diameter = BALL.Radius * 2
	local part = Instance.new("Part")
	part.Name = "Ball"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Color = BALL.Color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CustomPhysicalProperties = PhysicalProperties.new(BALL.Density, BALL.Friction, BALL.Elasticity, 1, BALL.ElasticityWeight)
	part.CollisionGroup = CharacterService.BALL_GROUP
	part.CFrame = CFrame.new(court.RackPosition)

	-- Three seams make it read as a basketball from any angle
	local seamSize = Vector3.new(0.05, diameter + 0.03, diameter + 0.03)
	for _, rotation in { CFrame.identity, CFrame.Angles(0, math.rad(90), 0), CFrame.Angles(0, 0, math.rad(90)) } do
		local seam = Instance.new("Part")
		seam.Name = "Seam"
		seam.Shape = Enum.PartType.Cylinder
		seam.Size = seamSize
		seam.Color = BALL.SeamColor
		seam.Material = Enum.Material.SmoothPlastic
		seam.Massless = true
		seam.CanCollide = false
		seam.CanQuery = false
		seam.CanTouch = false
		seam.CastShadow = false
		seam.CollisionGroup = CharacterService.BALL_GROUP
		seam.CFrame = part.CFrame * rotation
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = seam
		weld.Parent = seam
		seam.Parent = part
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "Center"
	attachment.Parent = part
	local antiGravity = Instance.new("VectorForce")
	antiGravity.Name = "AntiGravity"
	antiGravity.Attachment0 = attachment
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.Parent = part

	part:SetAttribute("CourtId", court.Id)
	part:SetAttribute("HolderUserId", 0)
	part:SetAttribute("Shooting", false)
	part.Parent = court.Model
	return part, antiGravity
end

function BallService.Create(court: any): Ball
	local part, antiGravity = createBallPart(court)
	local ball: Ball = {
		Court = court,
		Part = part,
		AntiGravity = antiGravity,
		Weld = nil,
		State = "Dead",
		StateSince = os.clock(),
		Holder = nil,
		LastTouch = nil,
		Shot = nil,
		LastPosition = part.Position,
		NoPickupUntil = {},
		PickupFilter = nil,
		EnforceBounds = false,
		LooseTimeout = BALL.LooseTimeout,
		TouchedHoop = false,
		TouchedRim = false,
	}
	part.Touched:Connect(function(hit)
		local group = hit.CollisionGroup
		if (group ~= Config.Collision.Hoop and group ~= Config.Collision.Rim) or (ball.State ~= "InFlight" and ball.State ~= "Loose") then
			return
		end
		-- Bumping the hoop from underneath on the way up can never be part of a
		-- ball dropping in, so it does not count as a touch
		if part.Position.Y < court.RimCenter.Y - Config.Court.RimTube then
			return
		end
		ball.TouchedHoop = true
		if hit.Name == "Rim" then
			ball.TouchedRim = true
		end
	end)
	freePhysics(ball)
	setState(ball, "Dead")
	table.insert(balls, ball)
	return ball
end

function BallService.GetBalls(): { Ball }
	return balls
end

function BallService.FindHeldBy(player: Player): Ball?
	for _, ball in balls do
		if ball.State == "Held" and ball.Holder == player then
			return ball
		end
	end
	return nil
end

-- Give the ball to a player. Fails if someone else holds it or the player has no character.
function BallService.GiveTo(ball: Ball, player: Player): boolean
	if ball.State == "Held" then
		if ball.Holder == player then
			return true
		end
		return false
	end
	-- One ball per player
	if BallService.FindHeldBy(player) then
		return false
	end
	local root = CharacterService.GetRoot(player)
	if not root then
		return false
	end
	if ball.Weld then
		ball.Weld:Destroy()
		ball.Weld = nil
	end
	local part = ball.Part
	ball.AntiGravity.Enabled = false
	part.Massless = true
	part.CanCollide = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CFrame = root.CFrame * BALL.HoldOffset

	local weld = Instance.new("Weld")
	weld.Name = "HoldWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = BALL.HoldOffset
	weld.Parent = part
	ball.Weld = weld

	ball.Shot = nil
	ball.LastTouch = player
	setHolder(ball, player)
	setState(ball, "Held")
	return true
end

-- Drop the ball where it is (keeps a little of the holder's momentum)
function BallService.Release(ball: Ball, newState: BallState?)
	local wasHeld = ball.State == "Held"
	freePhysics(ball)
	ball.TouchedHoop = false
	ball.TouchedRim = false
	if wasHeld and ball.Holder then
		ball.NoPickupUntil[ball.Holder] = os.clock() + 0.3
	end
	setHolder(ball, nil)
	ball.Shot = nil
	setState(ball, newState or "Loose")
end

-- Teleport the ball (not held) to a world position with no velocity
function BallService.PlaceAt(ball: Ball, position: Vector3, newState: BallState?)
	freePhysics(ball)
	ball.TouchedHoop = false
	ball.TouchedRim = false
	setHolder(ball, nil)
	ball.Shot = nil
	ball.Part.CFrame = CFrame.new(position)
	ball.Part.AssemblyLinearVelocity = Vector3.zero
	ball.Part.AssemblyAngularVelocity = Vector3.zero
	ball.LastPosition = position
	ball.NoPickupUntil = {}
	setState(ball, newState or "Loose")
end

function BallService.SetState(ball: Ball, state: BallState)
	if state == "Held" then
		error("Use BallService.GiveTo to hand a ball to a player")
	end
	if ball.State == "Held" then
		BallService.Release(ball, state)
		return
	end
	setState(ball, state)
end

function BallService.NewShotId(): number
	nextShotId += 1
	return nextShotId
end

-- Knock a held ball loose (steal poke, blocked shot). `toucher` becomes the
-- last touch for out-of-bounds; the old holder can't grab it back right away.
function BallService.Knock(ball: Ball, from: Vector3, velocity: Vector3, toucher: Player, regrabDelay: number, toucherDelay: number?): boolean
	if ball.State ~= "Held" then
		return false
	end
	local previous = ball.Holder
	freePhysics(ball)
	ball.TouchedHoop = false
	ball.TouchedRim = false
	setHolder(ball, nil)
	ball.Shot = nil
	local part = ball.Part
	part.CFrame = CFrame.new(from)
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = Vector3.zero
	ball.LastPosition = from
	ball.LastTouch = toucher
	if previous then
		ball.NoPickupUntil[previous] = os.clock() + regrabDelay
	end
	if toucherDelay and toucherDelay > 0 then
		ball.NoPickupUntil[toucher] = os.clock() + toucherDelay
	end
	setState(ball, "Loose")
	return true
end

-- Launch a shot. Only valid while `shot.Shooter` holds the ball.
function BallService.Launch(ball: Ball, from: Vector3, velocity: Vector3, shot: ShotRecord): boolean
	if ball.State ~= "Held" or ball.Holder ~= shot.Shooter then
		return false
	end
	freePhysics(ball)
	ball.TouchedHoop = false
	ball.TouchedRim = false
	setHolder(ball, nil)
	local part = ball.Part
	part.CFrame = CFrame.new(from)
	part.AssemblyLinearVelocity = velocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude > 0.1 then
		-- Backspin around the axis perpendicular to the flight direction
		local spinAxis = flat.Unit:Cross(Vector3.yAxis)
		part.AssemblyAngularVelocity = spinAxis * Config.Shot.BackspinSpeed
	end
	ball.Shot = shot
	ball.LastTouch = shot.Shooter
	ball.LastPosition = from
	ball.NoPickupUntil[shot.Shooter] = os.clock() + BALL.ShooterRegrabDelay
	setState(ball, "InFlight")
	part.CollisionGroup = if shot.Made then CharacterService.BALL_MAKE_GROUP else CharacterService.BALL_GROUP
	return true
end

--------------------------------------------------------------------------------
-- Per-frame update (called from Main's single Heartbeat loop)
--------------------------------------------------------------------------------

local function tryPickup(ball: Ball, now: number)
	local filter = ball.PickupFilter
	if not filter then
		return
	end
	local position = ball.Part.Position
	local bestPlayer: Player? = nil
	local bestDistance = math.huge
	for _, player in Players:GetPlayers() do
		local blockedUntil = ball.NoPickupUntil[player]
		if (blockedUntil and blockedUntil > now) or CharacterService.IsSuspicious(player) then
			continue
		end
		local root = CharacterService.GetRoot(player)
		if not root then
			continue
		end
		local offset = position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if flat > BALL.PickupHorizontal or offset.Y < -BALL.PickupBelow or offset.Y > BALL.PickupAbove then
			continue
		end
		if flat < bestDistance and filter(player) and CharacterService.IsMoveLegit(player) then
			bestDistance = flat
			bestPlayer = player
		end
	end
	if bestPlayer and BallService.GiveTo(ball, bestPlayer) then
		BallService.PickedUp:Fire(ball, bestPlayer)
	end
end

local function updateBall(ball: Ball, now: number)
	local part = ball.Part
	if not part.Parent then
		return
	end
	local court = ball.Court
	local state = ball.State

	if state == "Held" then
		local holder = ball.Holder
		local root = holder and CharacterService.GetRoot(holder)
		local weld = ball.Weld
		if not holder or not root or not weld or weld.Parent ~= part or weld.Part0 ~= root then
			BallService.Release(ball, "Loose")
			return
		end
		if ball.EnforceBounds and not BasketballMath.IsInBounds(court.Origin, root.Position, 0) then
			BallService.OutOfBounds:Fire(ball, holder, "Stepped out of bounds")
		end
		ball.LastPosition = part.Position
		return
	end

	local position = part.Position
	if position.Y < BALL.KillHeight then
		BallService.Lost:Fire(ball)
		return
	end

	if state == "InFlight" then
		local rim: Vector3 = court.RimCenter
		local previous = ball.LastPosition
		if previous.Y >= rim.Y and position.Y < rim.Y then
			local alpha = (previous.Y - rim.Y) / math.max(previous.Y - position.Y, 1e-4)
			local crossing = previous:Lerp(position, alpha)
			local flat = Vector3.new(crossing.X - rim.X, 0, crossing.Z - rim.Z).Magnitude
			local shot = ball.Shot
			-- A decided make always counts; a decided miss only if it really
			-- bounced in off the rim or glass
			-- (a crossing this far out means the ball is overlapping the ring right now,
			-- even if the Touched event has not been delivered yet)
			local touchingRing = flat >= Config.Court.RimRadius - Config.Ball.Radius
			local legit = shot ~= nil and (shot.Made or ball.TouchedHoop or touchingRing)
			if flat <= Config.Court.RimRadius - 0.05 and legit then
				setState(ball, "Scored")
				ball.LastPosition = position
				if shot then
					BallService.Scored:Fire(ball, shot)
				end
				return
			end
		end
		local velocity = part.AssemblyLinearVelocity
		local cameDown = velocity.Y < 0 and position.Y < rim.Y - 1.2
		if cameDown or now - ball.StateSince > BALL.FlightTimeout then
			-- Missed: it is a live rebound now
			ball.Shot = nil
			setState(ball, "Loose")
		end
		ball.LastPosition = position
		return
	end

	if state == "Loose" then
		tryPickup(ball, now)
		if ball.State ~= "Loose" then
			return
		end
		if ball.EnforceBounds then
			local nearFloor = position.Y < court.Origin.Position.Y + 3
			if nearFloor and not BasketballMath.IsInBounds(court.Origin, position, BALL.Radius) then
				setState(ball, "Dead")
				BallService.OutOfBounds:Fire(ball, ball.LastTouch, "Out of bounds")
				return
			end
		end
		if now - ball.StateSince > ball.LooseTimeout then
			BallService.Lost:Fire(ball)
			return
		end
	end

	ball.LastPosition = position
end

function BallService.Update(_dt: number)
	local now = os.clock()
	for _, ball in balls do
		updateBall(ball, now)
	end
end

return BallService
