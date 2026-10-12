--!strict
-- UIKit (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > UIKit
-- Tiny helpers so every screen shares the same look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local UIKit = {}
UIKit.Theme = Config.UI

function UIKit.new(className: string, props: { [string]: any }?, children: { any }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.corner(radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.8,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return UIKit.new("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u })
end

function UIKit.gradient(top: Color3, bottom: Color3): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
	})
end

-- Text label with theme defaults
function UIKit.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = UIKit.Theme.Text,
		Font = UIKit.Theme.Font,
		TextScaled = true,
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.new("TextLabel", defaults)
end

-- Dark rounded panel
function UIKit.panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = UIKit.Theme.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local frame = UIKit.new("Frame", defaults)
	UIKit.corner(14).Parent = frame
	UIKit.stroke(Color3.new(1, 1, 1), 1.5, 0.85).Parent = frame
	return frame
end

function UIKit.tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

function UIKit.formatClock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(s // 60, s % 60)
end

return UIKit
