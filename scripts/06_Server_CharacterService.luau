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
local samples: { [Player]: Sample } = {}
local suspiciousUntil: { [Player]: number } = {}
local sampleTimer = 0

local function setupCollisionGroups()
	for _, group in { GROUPS.Players, GROUPS.InMatch, GROUPS.Ball, GROUPS.BallMake, GROUPS.Hoop } do
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

local function resetSample(player: Player)
	samples[player] = nil
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
		samples[player] = nil
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

	sampleTimer += dt
	if sampleTimer < ANTI.SampleInterval then
		return
	end
	sampleTimer = 0
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetRoot(player)
		if not root or frozen[player] then
			samples[player] = nil
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
		samples[player] = { Position = position, Time = now }
	end
end

return CharacterService
