--!strict
-- MovesController (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > MovesController
-- Steal (defense) and crossover (offense) input on keyboard, controller and
-- touch. Each press sends one request; the server decides what happens. The
-- quick sideways burst / forward lunge is applied locally so it feels instant.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent
local UIKit = require(Client:WaitForChild("UIKit"))
local MatchClient = require(Client:WaitForChild("MatchClient"))
local ShootController = require(Client:WaitForChild("ShootController"))

local MovesController = {}
MovesController.ScriptVersion = 2 -- Main/ClientMain compare this to spot an old copy; bump when this file changes

local MOVES = Config.Moves
local DEFENSE = Config.Defense
local STEAL_ACTION = "StreetHoops_Steal"
local CROSSOVER_ACTION = "StreetHoops_Crossover"
local player = Players.LocalPlayer

local stealRemote: RemoteEvent
local crossoverRemote: RemoteEvent
local lastSteal = -math.huge
local lastCrossover = -math.huge
local stealButton: TextButton
local moveButton: TextButton

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function burst(direction: Vector3, speed: number, duration: number)
	ShootController.Burst(direction, speed, duration)
end

local function canCrossover(): boolean
	return MatchClient.CanShootNow() and not ShootController.IsHolding()
end

-- Small margin over the server's cooldown so network jitter never drops a press
local COOLDOWN_MARGIN = 0.1

local function carrierRoot(): BasePart?
	local court = MatchClient.GetMyCourt()
	local ball = court and MatchClient.GetBall(court)
	local id = ball and ball:GetAttribute("HolderUserId")
	local carrier = if typeof(id) == "number" then Players:GetPlayerByUserId(id) else nil
	local character = carrier and carrier.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function tryCrossover(): boolean
	if not canCrossover() then
		return false
	end
	local now = os.clock()
	if now - lastCrossover < MOVES.CrossoverCooldown + COOLDOWN_MARGIN then
		return true -- still ours (swallow the key), just on cooldown
	end
	lastCrossover = now
	local ball = MatchClient.GetHeldBall()
	-- Cross to the other hand
	local direction = if ball and ball:GetAttribute("Hand") == "Left" then 1 else -1
	crossoverRemote:FireServer(direction)
	local root = getRoot()
	if root then
		burst(root.CFrame.RightVector * direction, MOVES.CrossoverSpeed, MOVES.CrossoverDuration)
	end
	return true
end

local function trySteal(): boolean
	if not MatchClient.CanStealNow() then
		return false
	end
	local now = os.clock()
	-- If this steal works and we grab the ball, the next mashed press of the
	-- same key must not turn into an instant airball
	ShootController.SuppressUntil(now + 0.4)
	if now - lastSteal < DEFENSE.StealCooldown + COOLDOWN_MARGIN then
		return true
	end
	lastSteal = now
	local root = getRoot()
	local target = carrierRoot()
	if root and target and not root.Anchored then
		-- Turn to face the ball carrier before reaching (the server checks facing)
		local toCarrier = target.Position - root.Position
		local flat = Vector3.new(toCarrier.X, 0, toCarrier.Z)
		if flat.Magnitude > 1e-3 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
			if flat.Magnitude <= DEFENSE.StealRange then
				burst(flat, MOVES.StealLungeSpeed, MOVES.StealLungeDuration)
			end
		end
	end
	stealRemote:FireServer()
	return true
end

local function makeButton(name: string, text: string, color: Color3): TextButton
	local touchButton = ShootController.GetTouchButton()
	local button = UIKit.new("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(90, 90),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		Text = text,
		TextColor3 = Config.UI.Text,
		Font = Config.UI.FontHeavy,
		TextScaled = true,
		AutoButtonColor = true,
		Selectable = false,
		Visible = false,
		Parent = touchButton.Parent,
	})
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = button })
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0.16, 0), PaddingRight = UDim.new(0.16, 0), Parent = button })
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 20, Parent = button })
	UIKit.stroke(Color3.new(1, 1, 1), 3, 0.3).Parent = button
	return button
end

-- STEAL takes SHOOT's spot (they never show together); MOVE sits just above SHOOT
local function layoutButtons()
	ShootController.LayoutTouchButton()
	local shoot = ShootController.GetTouchButton()
	stealButton.AnchorPoint = shoot.AnchorPoint
	stealButton.Position = shoot.Position
	stealButton.Size = shoot.Size
	local size = shoot.Size.X.Offset
	local moveSize = math.floor(size * 0.75)
	moveButton.AnchorPoint = shoot.AnchorPoint
	moveButton.Size = UDim2.fromOffset(moveSize, moveSize)
	local p = shoot.Position
	moveButton.Position = UDim2.new(p.X.Scale, p.X.Offset + (size - moveSize) / 2, p.Y.Scale, p.Y.Offset - moveSize - 12)
end

local function refreshTouch()
	local touch = UserInputService.TouchEnabled
	local showSteal = touch and MatchClient.CanStealNow()
	local showMove = touch and canCrossover()
	if (showSteal and not stealButton.Visible) or (showMove and not moveButton.Visible) then
		layoutButtons()
	end
	stealButton.Visible = showSteal
	moveButton.Visible = showMove
end

function MovesController.Init()
	stealRemote = Net.Event("Steal")
	crossoverRemote = Net.Event("Crossover")

	-- Bound after ShootController, so these get first look at the shared keys:
	-- E / X / R2 steal only when the opponent has the ball, otherwise they shoot.
	ContextActionService:BindAction(STEAL_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin and trySteal() then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.E, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction(CROSSOVER_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin and tryCrossover() then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)

	stealButton = makeButton("Steal", "STEAL", Config.UI.Home)
	moveButton = makeButton("Move", "MOVE", Config.UI.PanelLight)
	stealButton.Activated:Connect(function()
		trySteal()
	end)
	moveButton.Activated:Connect(function()
		tryCrossover()
	end)

	MatchClient.Changed:Connect(refreshTouch)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(layoutButtons)
		end)
	end
	refreshTouch()
end

return MovesController
