--!strict
-- CharacterService (ModuleScript) — ServerScriptService > Server > CharacterService
-- Character helpers shared by the other services: collision groups, movement
-- defaults, freezing, teleporting and "is this player alive" checks.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local CharacterService = {}

local GROUPS = Config.Collision
CharacterService.PLAYER_GROUP = GROUPS.Players
CharacterService.BALL_GROUP = GROUPS.Ball
CharacterService.BALL_MAKE_GROUP = GROUPS.BallMake

-- Fires (player) when a player's humanoid dies
CharacterService.Died = Signal.new()

local frozen: { [Player]: boolean } = {}

local function setupCollisionGroups()
	for _, group in { GROUPS.Players, GROUPS.Ball, GROUPS.BallMake, GROUPS.Rim } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	-- The ball passes through bodies; defence is handled by game logic, not physics shoves
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Players, GROUPS.Ball, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Players, GROUPS.BallMake, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.BallMake, GROUPS.Rim, false)
end

local function applyGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = CharacterService.PLAYER_GROUP
	end
end

local function applyMovement(humanoid: Humanoid, isFrozen: boolean)
	humanoid.UseJumpPower = false
	if isFrozen then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	else
		humanoid.WalkSpeed = Config.Movement.WalkSpeed
		humanoid.JumpHeight = Config.Movement.JumpHeight
	end
end

local function onCharacterAdded(player: Player, character: Model)
	for _, descendant in character:GetDescendants() do
		applyGroup(descendant)
	end
	character.DescendantAdded:Connect(applyGroup)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	applyMovement(humanoid, frozen[player] == true)
	humanoid.Died:Connect(function()
		CharacterService.Died:Fire(player)
	end)
end

function CharacterService.Init()
	setupCollisionGroups()
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
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function CharacterService.IsAlive(player: Player): boolean
	return player.Parent ~= nil and CharacterService.GetRoot(player) ~= nil
end

function CharacterService.SetFrozen(player: Player, isFrozen: boolean)
	if isFrozen then
		frozen[player] = true
	else
		frozen[player] = nil
	end
	local humanoid = CharacterService.GetHumanoid(player)
	if humanoid then
		applyMovement(humanoid, isFrozen)
	end
end

function CharacterService.Teleport(player: Player, cframe: CFrame)
	local character = player.Character
	local root = CharacterService.GetRoot(player)
	if not character or not root then
		return
	end
	-- Keep the character's own orientation offset relative to the root
	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

return CharacterService
