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
ShootController.ScriptVersion = 3 -- ClientMain compares this to spot an old copy; bump when this file changes
ShootController.ScriptFile = "17_Client_ShootController" -- and this to spot another file's code pasted here

local SHOT = Config.Shot
local FINISH = Config.Finish
local ACTION = "StreetHoops_Shoot"
local player = Players.LocalPlayer

local shootStart: RemoteEvent
local shootRelease: RemoteEvent
local finishRemote: RemoteEvent

local holding = false
local startedAt = 0
local heldBall: BasePart? = nil
local savedWalkSpeed: number? = nil
local shotToken = 0
local lastBeganAt = -math.huge
local finishingUntil = 0 -- a layup/dunk is on its way: no second shot or crossover
local suppressUntil = 0 -- set by MovesController so a steal mash can't become an accidental shot
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

-- Setting humanoid.Jump from input code gets overwritten by the default
-- controls the same frame, so jump through the state machine instead
local function jumpNow(humanoid: Humanoid)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
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
	if holding or os.clock() < finishingUntil or not MatchClient.CanShootNow() then
		return
	end
	-- Mirror the server's rate limit so we never show a meter for a shot it would drop
	if os.clock() - lastBeganAt < SHOT.MinShotInterval + 0.05 or os.clock() < suppressUntil then
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
		if holding and token == shotToken and humanoid.Parent then
			jumpNow(humanoid)
		end
	end)
end

-- Holds our own character's horizontal velocity (we own its physics) until
-- the returned attachment is destroyed. Vertical movement is left alone.
local function planeVelocity(root: BasePart, velocity: Vector3): (LinearVelocity, Attachment)
	local attachment = Instance.new("Attachment")
	attachment.Name = "StreetHoopsBurst"
	attachment.Parent = root
	local constraint = Instance.new("LinearVelocity")
	constraint.Attachment0 = attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	constraint.PrimaryTangentAxis = Vector3.xAxis
	constraint.SecondaryTangentAxis = Vector3.zAxis
	constraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	constraint.MaxForce = 1e5
	constraint.Parent = root
	return constraint, attachment
end

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root.Anchored then
		return root
	end
	return nil
end

-- Short burst of horizontal velocity. Also used by MovesController for
-- crossovers and steal lunges.
local function burst(direction: Vector3, speed: number, duration: number)
	local root = getRoot()
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if not root or flat.Magnitude < 1e-3 or speed <= 0 then
		return
	end
	local _, attachment = planeVelocity(root, flat.Unit * speed)
	task.delay(duration, function()
		attachment:Destroy()
	end)
end
ShootController.Burst = burst

-- Dunk leap: carry our speed (never brake) to just short of the rim, then hang
-- there so we come down in front of the hoop instead of drifting under the glass
local function dunkLeap(root: BasePart, humanoid: Humanoid, toward: Vector3)
	local distance = toward.Magnitude
	local direction = if distance > 1e-3 then toward.Unit else Vector3.zero
	local travel = math.max(0, distance - FINISH.DunkStopShort)
	local v = root.AssemblyLinearVelocity
	local current = math.max(0, Vector3.new(v.X, 0, v.Z):Dot(direction))
	local speed = math.min(math.max(current, travel / FINISH.DunkLeapTime), FINISH.DunkLeapMaxSpeed)
	local duration = if speed > 0 then travel / speed else 0
	local constraint, attachment = planeVelocity(root, direction * speed)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= duration then
			constraint.PlaneVelocity = Vector2.zero
		end
		local landed = elapsed > 0.15 and humanoid.FloorMaterial ~= Enum.Material.Air
		if landed or elapsed >= FINISH.DunkHangTime or not attachment.Parent or root.Anchored then
			connection:Disconnect()
			attachment:Destroy()
		end
	end)
end

-- Driving at the rim? Then shoot means layup/dunk (no meter). The prediction
-- is a little stricter than the server's check so the two nearly always agree.
local function tryFinish(): boolean
	local now = os.clock()
	if holding or now < finishingUntil or not MatchClient.CanShootNow() then
		return false
	end
	if now - lastBeganAt < SHOT.MinShotInterval + 0.05 or now < suppressUntil then
		return false
	end
	local kind, rim = MatchClient.PredictFinish()
	local humanoid = getHumanoid()
	local root = getRoot()
	if not kind or not rim or not humanoid or humanoid.Health <= 0 or not root then
		return false
	end
	lastBeganAt = now
	finishingUntil = now + math.max(FINISH.DunkTime, FINISH.LayupTime) + 0.3
	shotToken += 1
	-- Tell the server which move we played; it may downgrade a dunk, never upgrade
	finishRemote:FireServer(shotToken, kind)

	local toward = Vector3.new(rim.X - root.Position.X, 0, rim.Z - root.Position.Z)
	jumpNow(humanoid)
	if kind == "Dunk" then
		dunkLeap(root, humanoid, toward)
	else
		burst(toward, FINISH.LayupHopSpeed, FINISH.LayupHopTime)
	end
	return true
end

local function onAction(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		if not MatchClient.CanShootNow() then
			return Enum.ContextActionResult.Pass
		end
		if tryFinish() then
			return Enum.ContextActionResult.Sink
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
		if not wasHolding and tryFinish() then
			return -- layup/dunk: fires on the press, nothing to hold
		end
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
	finishRemote = Net.Event("Finish")
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
		if kind ~= "ShotRejected" or typeof(data) ~= "table" then
			return
		end
		-- A server wait applies to us whichever shot caused it: hold off rather
		-- than show a meter it would refuse
		local retryIn = tonumber(data.RetryIn)
		if retryIn and retryIn > 0 then
			suppressUntil = math.max(suppressUntil, os.clock() + math.min(retryIn, 3))
		end
		if data.Token == shotToken then
			-- This shot was refused: the next press may go straight away
			finishingUntil = 0
			lastBeganAt = -math.huge
			if holding then
				holding = false
				heldBall = nil
				restoreWalkSpeed()
				stopTrackingTouch()
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		holding = false
		heldBall = nil
		savedWalkSpeed = nil
		finishingUntil = 0
		stopTrackingTouch()
		ShotMeter.Cancel()
	end)
end

-- True while a jump shot is held or a layup/dunk is on its way
function ShootController.IsHolding(): boolean
	return holding or os.clock() < finishingUntil
end

-- Ignore shot presses until `untilTime` (os.clock); never shortens an existing lockout
function ShootController.SuppressUntil(untilTime: number)
	suppressUntil = math.max(suppressUntil, untilTime)
end

-- The SHOOT touch button (MovesController lays its STEAL/MOVE buttons out from it)
function ShootController.GetTouchButton(): TextButton
	return touchButton
end

function ShootController.LayoutTouchButton()
	placeTouchButton()
end

return ShootController
