--!strict
-- BallVisuals (ModuleScript) — StarterPlayerScripts > ClientMain > BallVisuals
-- Cosmetic, local-only ball presentation: a dribble bounce while held, the ball
-- raised during a shot, an outline so it is easy to spot, and a possession
-- marker over the holder's head. None of this affects gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent
local UIKit = require(Client:WaitForChild("UIKit"))
local MatchClient = require(Client:WaitForChild("MatchClient"))

local BallVisuals = {}

local BALL = Config.Ball
local localPlayer = Players.LocalPlayer

type Visual = {
	Ball: BasePart,
	Highlight: Highlight,
	Marker: BillboardGui,
	Phase: number,
	CurrentOffset: CFrame,
}

local visuals: { [BasePart]: Visual } = {}

local function createVisual(ball: BasePart): Visual
	local highlight = UIKit.new("Highlight", {
		Name = "BallOutline",
		FillTransparency = 1,
		OutlineColor = Color3.fromRGB(255, 220, 160),
		OutlineTransparency = 0.35,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Adornee = ball,
		Parent = ball,
	})

	local marker = UIKit.new("BillboardGui", {
		Name = "PossessionMarker",
		Size = UDim2.fromOffset(120, 34),
		StudsOffset = Vector3.new(0, 3.2, 0),
		AlwaysOnTop = true,
		Enabled = false,
		LightInfluence = 0,
		MaxDistance = 140,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	local pill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Config.UI.Panel,
		BackgroundTransparency = 0.15,
		Parent = marker,
	})
	UIKit.corner(17).Parent = pill
	UIKit.stroke(Config.UI.Accent, 2, 0.1).Parent = pill
	UIKit.new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Config.Ball.Color,
		Parent = pill,
		}, { UIKit.corner(9) })
	UIKit.text({
		Name = "Label",
		Position = UDim2.fromOffset(32, 5),
		Size = UDim2.new(1, -40, 1, -10),
		Text = "BALL",
		Font = Config.UI.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = pill,
	})

	return {
		Ball = ball,
		Highlight = highlight,
		Marker = marker,
		Phase = 0,
		CurrentOffset = BALL.HoldOffset,
	}
end

local function ensureVisuals()
	for _, court in MatchClient.GetCourts() do
		local ball = MatchClient.GetBall(court)
		if ball and not visuals[ball] then
			visuals[ball] = createVisual(ball)
			ball.Destroying:Connect(function()
				local v = visuals[ball]
				if v then
					v.Marker:Destroy()
					visuals[ball] = nil
				end
			end)
		end
	end
end

local function updateVisual(v: Visual, dt: number)
	local ball = v.Ball
	local holderId = ball:GetAttribute("HolderUserId")
	local holder = if typeof(holderId) == "number" and holderId ~= 0 then Players:GetPlayerByUserId(holderId) else nil
	local character = holder and holder.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")

	if not holder or not root or not root:IsA("BasePart") then
		v.Marker.Enabled = false
		(v.Marker :: any).Adornee = nil
		return
	end

	v.Marker.Adornee = if head and head:IsA("BasePart") then head else root
	v.Marker.Enabled = holder ~= localPlayer
	local label = v.Marker:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = holder.DisplayName
	end

	local weld = ball:FindFirstChild("HoldWeld")
	if not weld or not weld:IsA("Weld") then
		return
	end

	local target: CFrame
	if ball:GetAttribute("Shooting") == true then
		target = BALL.ShootPoseOffset
	else
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local rate = BALL.DribbleRate * (0.6 + 0.4 * math.clamp(speed / Config.Movement.WalkSpeed, 0, 1))
		v.Phase = (v.Phase + dt * rate) % 1
		local hold = BALL.HoldOffset
		local height = math.abs(math.sin(v.Phase * math.pi))
		local y = BALL.DribbleFloorOffset + (hold.Y - BALL.DribbleFloorOffset) * height
		target = CFrame.new(hold.X, y, hold.Z)
	end
	-- Ease toward the shot pose, snap for the dribble so the bounce stays crisp
	local alpha = if ball:GetAttribute("Shooting") == true then math.clamp(dt * 14, 0, 1) else 1
	v.CurrentOffset = v.CurrentOffset:Lerp(target, alpha)
	weld.C0 = v.CurrentOffset
end

function BallVisuals.Init()
	MatchClient.Changed:Connect(ensureVisuals)
	ensureVisuals()
	RunService.RenderStepped:Connect(function(dt)
		for _, v in visuals do
			updateVisual(v, dt)
		end
	end)
end

return BallVisuals
