--!strict
-- ShootController (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > ShootController
-- Turns input (keyboard E, gamepad X/R2, touch SHOOT button) into shot requests.
-- Sends exactly two events per shot: ShootStart on press, ShootRelease on let go.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local BasketballMath = require(Shared:WaitForChild("BasketballMath"))

local Client = script.Parent
local UIKit = require(Client:WaitForChild("UIKit"))
local MatchClient = require(Client:WaitForChild("MatchClient"))
local ShotMeter = require(Client:WaitForChild("ShotMeter"))

local ShootController = {}

local SHOT = Config.Shot
local ACTION = "StreetHoops_Shoot"
local player = Players.LocalPlayer

local shootStart: RemoteEvent
local shootRelease: RemoteEvent

local holding = false
local startedAt = 0
local heldBall: BasePart? = nil
local savedWalkSpeed: number? = nil
local shotToken = 0
local lastBeganAt = -math.huge
local touchButton: TextButton
local touchScreenGui: ScreenGui
local touchConnection: RBXScriptConnection? = nil

local function stopTrackingTouch()
	if touchConnection then
		touchConnection:Disconnect()
		touchConnection = nil
	end
	if touchButton then
		touchButton.BackgroundTransparency = 0.1
	end
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function restoreWalkSpeed()
	local humanoid = getHumanoid()
	-- Only undo our own slow-down; the server may have frozen us meanwhile
	if humanoid and savedWalkSpeed and humanoid.WalkSpeed == Config.Movement.ShootingWalkSpeed then
		humanoid.WalkSpeed = savedWalkSpeed
	end
	savedWalkSpeed = nil
end

local function release(cancelled: boolean)
	if not holding then
		return
	end
	holding = false
	local hold = os.clock() - startedAt
	shootRelease:FireServer(hold)
	restoreWalkSpeed()
	if cancelled then
		ShotMeter.Cancel()
	else
		-- Provisional grade from our own clock; ShotMeter swaps in the server's
		-- grade when the "Release" feedback arrives
		local quality = BasketballMath.ClassifyRelease(hold / SHOT.FillTime)
		ShotMeter.Finish(quality)
	end
	heldBall = nil
end

local function begin()
	if holding or not MatchClient.CanShootNow() then
		return
	end
	-- Mirror the server's rate limit so we never show a meter for a shot it would drop
	if os.clock() - lastBeganAt < SHOT.MinShotInterval + 0.05 then
		return
	end
	local ball = MatchClient.GetHeldBall()
	local humanoid = getHumanoid()
	if not ball or not humanoid or humanoid.Health <= 0 then
		return
	end
	holding = true
	heldBall = ball
	startedAt = os.clock()
	lastBeganAt = startedAt
	shotToken += 1
	shootStart:FireServer(shotToken)
	ShotMeter.Begin(shotToken)

	if humanoid.WalkSpeed > Config.Movement.ShootingWalkSpeed then
		savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = Config.Movement.ShootingWalkSpeed
	end

	-- Time the jump so the player peaks right around the ideal release
	local idealTime = SHOT.FillTime * SHOT.IdealFraction
	local timeToApex = math.sqrt(2 * math.max(humanoid.JumpHeight, 0.1) / workspace.Gravity)
	local token = shotToken
	task.delay(math.max(0, idealTime - timeToApex), function()
		if holding and token == shotToken and humanoid.Parent and humanoid.FloorMaterial ~= Enum.Material.Air then
			humanoid.Jump = true
		end
	end)
end

local function onAction(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		if not MatchClient.CanShootNow() then
			return Enum.ContextActionResult.Pass
		end
		begin()
		return Enum.ContextActionResult.Sink
	elseif state == Enum.UserInputState.End then
		if holding then
			release(false)
			return Enum.ContextActionResult.Sink
		end
	elseif state == Enum.UserInputState.Cancel then
		release(true)
	end
	return Enum.ContextActionResult.Pass
end

-- Put SHOOT just left of the Roblox jump button, matching its size, on any screen
local function placeTouchButton()
	local playerGui = player:FindFirstChild("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	local gap = 14
	if touchGui and touchGui:IsA("ScreenGui") and jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		-- Share the touch controls' coordinate space so absolute positions line up
		touchScreenGui.IgnoreGuiInset = touchGui.IgnoreGuiInset
		pcall(function()
			(touchScreenGui :: any).ScreenInsets = (touchGui :: any).ScreenInsets
		end)
		local jumpSize = jump.AbsoluteSize.X
		local size = math.floor(jumpSize * 0.95)
		touchButton.AnchorPoint = Vector2.zero
		touchButton.Size = UDim2.fromOffset(size, size)
		touchButton.Position = UDim2.fromOffset(jump.AbsolutePosition.X - size - gap, jump.AbsolutePosition.Y + jumpSize - size)
		return
	end
	-- No touch controls found yet: use the same layout rule as PlayerModule's TouchJump
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local jumpSize = if small then 70 else 120
	local jumpX = if small then -95 else -170
	local jumpY = if small then -90 else -210
	local size = math.floor(jumpSize * 0.95)
	touchButton.AnchorPoint = Vector2.zero
	touchButton.Size = UDim2.fromOffset(size, size)
	touchButton.Position = UDim2.new(1, jumpX - size - gap, 1, jumpY + jumpSize - size)
end

local function buildTouchButton()
	local gui = UIKit.new("ScreenGui", {
		Name = "StreetHoopsTouch",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	touchButton = UIKit.new("TextButton", {
		Name = "Shoot",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(104, 104),
		BackgroundColor3 = Config.UI.Accent,
		BackgroundTransparency = 0.1,
		Text = "SHOOT",
		TextColor3 = Config.UI.Text,
		Font = Config.UI.FontHeavy,
		TextScaled = true,
		AutoButtonColor = false,
		Visible = false,
		Parent = gui,
	})
	touchScreenGui = gui
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = touchButton })
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0.16, 0), PaddingRight = UDim.new(0.16, 0), Parent = touchButton })
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 22, Parent = touchButton })
	UIKit.stroke(Color3.new(1, 1, 1), 3, 0.3).Parent = touchButton

	touchButton.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		-- Only the touch that started the shot may release it (a second finger
		-- brushing the button must not cut the shot short)
		local wasHolding = holding
		begin()
		if wasHolding or not holding then
			return
		end
		stopTrackingTouch()
		touchButton.BackgroundTransparency = 0.4
		-- Track this exact touch so dragging off the button still releases
		touchConnection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				stopTrackingTouch()
				release(false)
			end
		end)
	end)
end

function ShootController.Init()
	shootStart = Net.Event("ShootStart")
	shootRelease = Net.Event("ShootRelease")
	buildTouchButton()

	ContextActionService:BindAction(ACTION, onAction, false, Enum.KeyCode.E, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonR2)

	RunService.RenderStepped:Connect(function()
		if holding then
			-- Ball taken away or court state changed mid-shot
			if not heldBall or heldBall:GetAttribute("HolderUserId") ~= player.UserId or not MatchClient.CanShootNow() then
				release(true)
				return
			end
			local fraction = (os.clock() - startedAt) / SHOT.FillTime
			ShotMeter.SetFraction(fraction)
			if fraction >= SHOT.MaxHoldFraction then
				release(false)
			end
		end
	end)

	local function refreshTouch()
		local show = UserInputService.TouchEnabled and MatchClient.CanShootNow()
		if show and not touchButton.Visible then
			placeTouchButton()
		end
		touchButton.Visible = show
	end
	MatchClient.Changed:Connect(refreshTouch)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(placeTouchButton) -- after the touch controls re-layout
		end)
	end
	refreshTouch()

	Net.Event("Feedback").OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "ShotRejected" and typeof(data) == "table" and data.Token == shotToken and holding then
			holding = false
			heldBall = nil
			restoreWalkSpeed()
			stopTrackingTouch()
		end
	end)

	player.CharacterAdded:Connect(function()
		holding = false
		heldBall = nil
		savedWalkSpeed = nil
		stopTrackingTouch()
		ShotMeter.Cancel()
	end)
end

function ShootController.IsHolding(): boolean
	return holding
end

return ShootController
