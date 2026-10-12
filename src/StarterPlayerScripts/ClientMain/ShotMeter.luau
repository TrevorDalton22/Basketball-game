--!strict
-- ShotMeter (ModuleScript) — StarterPlayerScripts > ClientMain > ShotMeter
-- Vertical timing meter that floats beside the local character while a shot
-- is held. Purely visual: the server re-measures the hold and decides the shot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local ShotMeter = {}

local SHOT = Config.Shot
local THEME = Config.UI
local player = Players.LocalPlayer

local billboard: BillboardGui
local container: Frame
local fill: Frame
local label: TextLabel
local hideToken = 0

-- Meter height represents 0 .. MaxHoldFraction
local function toScale(fraction: number): number
	return math.clamp(fraction / SHOT.MaxHoldFraction, 0, 1)
end

local function zone(parent: Instance, center: number, halfWidth: number, color: Color3, transparency: number)
	local bottom = toScale(center - halfWidth)
	local top = toScale(center + halfWidth)
	UIKit.new("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1 - bottom),
		Size = UDim2.fromScale(1, top - bottom),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = parent,
	})
end

function ShotMeter.Init()
	billboard = UIKit.new("BillboardGui", {
		Name = "StreetHoopsShotMeter",
		Size = UDim2.fromOffset(34, 150),
		StudsOffset = Vector3.new(2.8, 1.2, 0),
		AlwaysOnTop = true,
		ResetOnSpawn = false,
		Enabled = false,
		LightInfluence = 0,
		Parent = player:WaitForChild("PlayerGui"),
	})

	container = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -26),
		BackgroundTransparency = 1,
		Parent = billboard,
	})

	local track = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 18, 1, 0),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = container,
	})
	UIKit.corner(9).Parent = track
	UIKit.stroke(Color3.new(1, 1, 1), 2, 0.4).Parent = track

	zone(track, SHOT.IdealFraction, SHOT.GoodWindow, THEME.Good, 0.55)
	zone(track, SHOT.IdealFraction, SHOT.PerfectWindow, THEME.Perfect, 0.05)

	fill = UIKit.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = track,
	})

	label = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(120, 22),
		Font = THEME.FontHeavy,
		TextStrokeTransparency = 0.3,
		Text = "",
		Parent = billboard,
	})
end

local function attach(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	billboard.Adornee = root
	return true
end

function ShotMeter.Begin()
	hideToken += 1
	if not attach() then
		return
	end
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	container.Size = UDim2.new(1, 0, 1, -26)
	billboard.Enabled = true
end

function ShotMeter.SetFraction(fraction: number)
	fill.Size = UDim2.fromScale(1, toScale(fraction))
end

local QUALITY_COLORS = {
	Perfect = THEME.Perfect,
	Good = THEME.Good,
	Early = THEME.Bad,
	Late = THEME.Bad,
}

local QUALITY_TEXT = {
	Perfect = "PERFECT",
	Good = "GOOD",
	Early = "EARLY",
	Late = "LATE",
}

local function hideSoon(delaySeconds: number)
	hideToken += 1
	local token = hideToken
	task.delay(delaySeconds, function()
		if token == hideToken then
			billboard.Enabled = false
		end
	end)
end

function ShotMeter.Finish(quality: string)
	local color = QUALITY_COLORS[quality] or THEME.Text
	fill.BackgroundColor3 = color
	label.Text = QUALITY_TEXT[quality] or quality
	label.TextColor3 = color
	hideSoon(0.8)
end

function ShotMeter.Cancel()
	label.Text = ""
	hideSoon(0)
end

return ShotMeter
