--!strict
-- ShootController (ModuleScript) — StarterPlayerScripts > ClientMain > ShootController
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
local touchButton: TextButton

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
		local quality = BasketballMath.ClassifyRelease(hold / SHOT.FillTime)
		ShotMeter.Finish(quality)
	end
	heldBall = nil
end

local function begin()
	if holding or not MatchClient.CanShootNow() then
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
	shotToken += 1
	shootStart:FireServer()
	ShotMeter.Begin()

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
		Position = UDim2.new(1, -36, 1, -210),
		Size = UDim2.fromOffset(104, 104),
		BackgroundColor3 = Config.UI.Accent,
		BackgroundTransparency = 0.1,
		Text = "SHOOT",
		TextColor3 = Config.UI.Text,
		Font = Config.UI.FontHeavy,
		TextSize = 22,
		AutoButtonColor = false,
		Visible = false,
		Parent = gui,
	})
	UIKit.corner(52).Parent = touchButton
	UIKit.stroke(Color3.new(1, 1, 1), 3, 0.3).Parent = touchButton

	touchButton.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		begin()
		if not holding then
			return
		end
		touchButton.BackgroundTransparency = 0.4
		-- Track this exact touch so dragging off the button still releases
		local connection
		connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				connection:Disconnect()
				touchButton.BackgroundTransparency = 0.1
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
		touchButton.Visible = UserInputService.TouchEnabled and MatchClient.CanShootNow()
	end
	MatchClient.Changed:Connect(refreshTouch)
	refreshTouch()

	player.CharacterAdded:Connect(function()
		holding = false
		heldBall = nil
		savedWalkSpeed = nil
		ShotMeter.Cancel()
	end)
end

function ShootController.IsHolding(): boolean
	return holding
end

return ShootController
