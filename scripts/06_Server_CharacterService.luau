--!strict
-- CharacterService (ModuleScript) — ServerScriptService > Server > CharacterService
-- Character helpers shared by the other services: collision groups, movement
-- defaults, server-enforced freezing, teleporting, "is this player alive"
-- checks and a simple teleport/speed-hack detector.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local CharacterService = {}

local GROUPS = Config.Collision
local ANTI = Config.AntiCheat

CharacterService.BALL_GROUP = GROUPS.Ball
CharacterService.BALL_MAKE_GROUP = GROUPS.BallMake

-- Fires (player) when a player's humanoid dies
CharacterService.Died = Signal.new()

local frozen: { [Player]: boolean } = {}
local inMatch: { [Player]: boolean } = {}
-- Temporary slow-downs (missed steals, broken ankles): when they end and how slow
type Slow = { Until: number, Speed: number }
local slowed: { [Player]: Slow } = {}

type Sample = { Position: Vector3, Time: number }
local samples: { [Player]: Sample } = {} -- latest position sample (anti-teleport baseline)
local history: { [Player]: { Sample } } = {} -- last few samples, oldest first (speed measurement)
local HISTORY_LENGTH = 4
local suspiciousUntil: { [Player]: number } = {}
local sampleTimer = 0
-- Last time each match player was standing on something (checked every frame
-- for match players only). A real jump lasts about half a second, so a
-- "jumping" player who hasn't touched the ground for longer is hovering.
local groundedAt: { [Player]: number } = {}
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
-- Ray "as a match player": skips the ring/net (players pass through them) and balls
groundParams.CollisionGroup = Config.Collision.InMatch

local function setupCollisionGroups()
	for _, group in { GROUPS.Players, GROUPS.InMatch, GROUPS.Ball, GROUPS.BallMake, GROUPS.Hoop, GROUPS.Rim } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	-- Balls pass through bodies; defence is game logic, not physics shoves
	for _, body in { GROUPS.Players, GROUPS.InMatch } do
		PhysicsService:CollisionGroupSetCollidable(body, GROUPS.Ball, false)
		PhysicsService:CollisionGroupSetCollidable(body, GROUPS.BallMake, false)
	end
	-- Players in a match only bump into each other, never into bystanders
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Players, GROUPS.InMatch, false)
	-- A decided make ignores the hoop entirely
	PhysicsService:CollisionGroupSetCollidable(GROUPS.BallMake, GROUPS.Hoop, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.BallMake, GROUPS.Rim, false)
	-- Players never snag on the ring or net (dunks), but still hit the glass and pole
	for _, body in { GROUPS.Players, GROUPS.InMatch } do
		PhysicsService:CollisionGroupSetCollidable(body, GROUPS.Rim, false)
	end
end

local function groupFor(player: Player): string
	return if inMatch[player] then GROUPS.InMatch else GROUPS.Players
end

local function applyGroup(player: Player, instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = groupFor(player)
	end
end

local function getRootPart(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function applyMovement(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local isFrozen = frozen[player] == true
	local slow = slowed[player]
	humanoid.UseJumpPower = false
	humanoid.WalkSpeed = if isFrozen then 0 elseif slow then slow.Speed else Config.Movement.WalkSpeed
	humanoid.JumpHeight = if isFrozen then 0 else Config.Movement.JumpHeight
	-- Anchoring on the server is what actually holds the player in place:
	-- the client owns its character physics and could ignore WalkSpeed.
	local root = getRootPart(character)
	if root then
		root.Anchored = isFrozen
	end
end

-- Start a fresh baseline at the player's current (server-known) position. Never
-- leave it empty: an empty baseline would accept any position as legit.
local function resetSample(player: Player)
	local character = player.Character
	local root = character and getRootPart(character)
	if root then
		local seed = { Position = root.Position, Time = os.clock() }
		samples[player] = seed
		history[player] = { seed }
	else
		samples[player] = nil
		history[player] = nil
	end
end

local function onCharacterAdded(player: Player, character: Model)
	resetSample(player)
	for _, descendant in character:GetDescendants() do
		applyGroup(player, descendant)
	end
	character.DescendantAdded:Connect(function(descendant)
		applyGroup(player, descendant)
	end)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	applyMovement(player)
	humanoid.Died:Connect(function()
		CharacterService.Died:Fire(player)
	end)
end

function CharacterService.Init()
	setupCollisionGroups()
	Players.RespawnTime = Config.Players.RespawnTime
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		frozen[player] = nil
		inMatch[player] = nil
		slowed[player] = nil
		groundedAt[player] = nil
		samples[player] = nil
		history[player] = nil
		suspiciousUntil[player] = nil
	end)
end

function CharacterService.GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Root part of a living character, or nil
function CharacterService.GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	if not CharacterService.GetHumanoid(player) then
		return nil
	end
	return getRootPart(character)
end

function CharacterService.IsAlive(player: Player): boolean
	return player.Parent ~= nil and CharacterService.GetRoot(player) ~= nil
end

function CharacterService.SetFrozen(player: Player, isFrozen: boolean)
	-- Departed players are never stored, so nothing leaks
	if isFrozen and player.Parent then
		frozen[player] = true
	else
		frozen[player] = nil
	end
	applyMovement(player)
	resetSample(player)
end

-- Slow a player's running for a moment (stacks by taking the slower/longer one)
function CharacterService.Slow(player: Player, duration: number, speed: number)
	if not player.Parent then
		return
	end
	local untilTime = os.clock() + duration
	local current = slowed[player]
	if current then
		untilTime = math.max(untilTime, current.Until)
		speed = math.min(speed, current.Speed)
	end
	slowed[player] = { Until = untilTime, Speed = speed }
	applyMovement(player)
end

function CharacterService.IsSlowed(player: Player): boolean
	return slowed[player] ~= nil
end

-- Participants collide with each other but not with bystanders
function CharacterService.SetInMatch(player: Player, value: boolean)
	if value and player.Parent then
		inMatch[player] = true
	else
		inMatch[player] = nil
		groundedAt[player] = nil
	end
	local character = player.Character
	if character then
		for _, descendant in character:GetDescendants() do
			applyGroup(player, descendant)
		end
	end
end

function CharacterService.Teleport(player: Player, cframe: CFrame)
	local character = player.Character
	local root = CharacterService.GetRoot(player)
	if not character or not root then
		return
	end
	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	resetSample(player) -- a server teleport is not a speed hack
end

-- How high a standing character's root sits above the floor (R15 and R6)
function CharacterService.StandingHeight(humanoid: Humanoid, root: BasePart): number
	local height = humanoid.HipHeight + root.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local character = humanoid.Parent
		local leg = character and character:FindFirstChild("Left Leg")
		height += if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	end
	return height
end

-- Has this match player stood on solid ground within the last `seconds`?
function CharacterService.WasGroundedWithin(player: Player, seconds: number): boolean
	local at = groundedAt[player]
	return at ~= nil and os.clock() - at <= seconds
end

-- How fast the player has really been moving along `direction` (studs/s),
-- measured by the server from their recent positions (never the velocity the
-- client reports). Uses the best of the last few sample windows, so a quick
-- sideways move (crossover) just before driving doesn't hide the drive.
function CharacterService.ApproachSpeed(player: Player, direction: Vector3): number
	local root = CharacterService.GetRoot(player)
	local list = history[player]
	if not root or not list or direction.Magnitude < 1e-3 then
		return 0
	end
	local dir = Vector3.new(direction.X, 0, direction.Z).Unit
	local now = os.clock()
	local position = root.Position
	local best = 0
	for _, sample in list do
		local elapsed = now - sample.Time
		if elapsed >= 0.1 and elapsed <= 0.8 then
			local delta = position - sample.Position
			best = math.max(best, Vector3.new(delta.X, 0, delta.Z):Dot(dir) / elapsed)
		end
	end
	return math.min(best, ANTI.MaxFlatSpeed)
end

-- Seconds since this match player last stood on the ground (math.huge if never)
function CharacterService.TimeSinceGrounded(player: Player): number
	local at = groundedAt[player]
	return if at then os.clock() - at else math.huge
end

local function trackGround(player: Player, clock: number)
	local character = player.Character
	local root = CharacterService.GetRoot(player)
	local humanoid = CharacterService.GetHumanoid(player)
	if not character or not root or not humanoid then
		return
	end
	if root.Anchored then
		groundedAt[player] = clock -- frozen on a check spot
		return
	end
	-- Bodies never count as ground (no standing on the shooter's head)
	local bodies: { Instance } = {}
	for other in inMatch do
		if other.Character then
			table.insert(bodies, other.Character)
		end
	end
	if not table.find(bodies, character) then
		table.insert(bodies, character)
	end
	groundParams.FilterDescendantsInstances = bodies
	-- Short ray: "grounded" must never overlap "high enough to block"
	local standing = CharacterService.StandingHeight(humanoid, root)
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(standing + Config.Defense.GroundedTolerance), 0), groundParams)
	if hit then
		groundedAt[player] = clock
	end
end

-- Checks a player's position right now against their last sample, so a quick
-- teleport-and-back between samples is still caught at the moment it matters
-- (steals, blocks, pickups). Returns false (and flags them) if it's impossible.
function CharacterService.IsMoveLegit(player: Player): boolean
	if CharacterService.IsSuspicious(player) then
		return false
	end
	local root = CharacterService.GetRoot(player)
	local last = samples[player]
	if not root or not last then
		return root ~= nil
	end
	local now = os.clock()
	local delta = root.Position - last.Position
	local flatDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if flatDistance > ANTI.MaxFlatSpeed * (now - last.Time) + 2 then
		suspiciousUntil[player] = now + ANTI.PenaltyTime
		return false
	end
	return true
end

-- True while a player is serving a penalty for moving impossibly fast
function CharacterService.IsSuspicious(player: Player): boolean
	local untilTime = suspiciousUntil[player]
	return untilTime ~= nil and untilTime > os.clock()
end

-- Called from Main's Heartbeat. Samples positions a few times a second and
-- flags anyone whose horizontal speed is far beyond what running allows.
function CharacterService.Update(dt: number)
	-- End expired slow-downs
	local clock = os.clock()
	for player, slow in slowed do
		if clock >= slow.Until then
			slowed[player] = nil
			applyMovement(player)
		end
	end
	for player in inMatch do
		trackGround(player, clock)
	end

	sampleTimer += dt
	if sampleTimer < ANTI.SampleInterval then
		return
	end
	sampleTimer = 0
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetRoot(player)
		if not root then
			samples[player] = nil
			history[player] = nil
			continue
		end
		if frozen[player] then
			-- Anchored by the server, so its position is authoritative: keep the
			-- baseline fresh so there's no gap right after the unfreeze
			resetSample(player)
			continue
		end
		local position = root.Position
		local last = samples[player]
		if last then
			local elapsed = now - last.Time
			local delta = position - last.Position
			local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
			if elapsed > 0 and flat / elapsed > ANTI.MaxFlatSpeed then
				suspiciousUntil[player] = now + ANTI.PenaltyTime
			end
		end
		local sample = { Position = position, Time = now }
		samples[player] = sample
		local list = history[player] or {}
		table.insert(list, sample)
		if #list > HISTORY_LENGTH then
			table.remove(list, 1)
		end
		history[player] = list
	end
end

return CharacterService
