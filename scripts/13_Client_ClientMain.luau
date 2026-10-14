--!strict
-- ClientMain (LocalScript) — StarterPlayer > StarterPlayerScripts > ClientMain
-- Client entry point. Its children are the client modules; this script loads
-- them, checks none is an old copy, and starts them in the right order. Any
-- problem is printed in Output and shown on screen, naming the file to paste.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TAG = "[Street Hoops]"

-- Pasted into the wrong script? Say so instead of waiting forever.
if game:GetService("RunService"):IsServer() then
	warn(("%s ✗ %s contains the ClientMain code (scripts/13_Client_ClientMain.luau). Paste that code into the ClientMain LocalScript, and put scripts/05_Server_Main.luau in ServerScriptService > Server > Main."):format(TAG, script:GetFullName()))
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CLIENT_PATH = "StarterPlayer > StarterPlayerScripts > ClientMain > "

-- Every module the client uses, with the ScriptVersion it must report (a
-- module without one counts as 1). Main checks the server modules the same way.
type Module = { Name: string, Parent: Instance, Where: string, File: string, Version: number }
local MODULES: { Module } = {
	{ Name = "Config", Parent = Shared, Where = "ReplicatedStorage > Shared > Config", File = "01_Shared_Config", Version = 2 },
	{ Name = "Signal", Parent = Shared, Where = "ReplicatedStorage > Shared > Signal", File = "02_Shared_Signal", Version = 1 },
	{ Name = "Net", Parent = Shared, Where = "ReplicatedStorage > Shared > Net", File = "03_Shared_Net", Version = 2 },
	{ Name = "BasketballMath", Parent = Shared, Where = "ReplicatedStorage > Shared > BasketballMath", File = "04_Shared_BasketballMath", Version = 1 },
	{ Name = "UIKit", Parent = script, Where = CLIENT_PATH .. "UIKit", File = "14_Client_UIKit", Version = 1 },
	{ Name = "MatchClient", Parent = script, Where = CLIENT_PATH .. "MatchClient", File = "15_Client_MatchClient", Version = 2 },
	{ Name = "ShotMeter", Parent = script, Where = CLIENT_PATH .. "ShotMeter", File = "16_Client_ShotMeter", Version = 1 },
	{ Name = "ShootController", Parent = script, Where = CLIENT_PATH .. "ShootController", File = "17_Client_ShootController", Version = 2 },
	{ Name = "BallVisuals", Parent = script, Where = CLIENT_PATH .. "BallVisuals", File = "18_Client_BallVisuals", Version = 2 },
	{ Name = "Hud", Parent = script, Where = CLIENT_PATH .. "Hud", File = "19_Client_Hud", Version = 2 },
	{ Name = "MovesController", Parent = script, Where = CLIENT_PATH .. "MovesController", File = "21_Client_MovesController", Version = 2 },
}

-- Start order matters: MovesController after ShootController so the
-- steal/crossover keys get first look when they apply
local START_ORDER = { "MatchClient", "Hud", "ShotMeter", "ShootController", "MovesController", "BallVisuals" }

local problems: { string } = {}
local notice: TextLabel? = nil

-- Set by the server's Main when its own setup check or start-up fails
local SERVER_PROBLEM = "StreetHoopsSetupProblem"
local function serverProblem(): string?
	local text = ReplicatedStorage:GetAttribute(SERVER_PROBLEM)
	return if typeof(text) == "string" and text ~= "" then text else nil
end

local function showProblems()
	local fromServer = serverProblem()
	if #problems == 0 and not fromServer then
		return
	end
	local lines = { "STREET HOOPS SETUP PROBLEM" }
	for i, text in problems do
		table.insert(lines, ("%d. %s"):format(i, text))
	end
	if fromServer then
		table.insert(lines, "The server reports: " .. fromServer)
	end
	table.insert(lines, "Fix these, then press Play again. Details are in View > Output.")
	if not notice then
		local gui = Instance.new("ScreenGui")
		gui.Name = "StreetHoopsSetupProblem"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 100
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 70)
		label.Size = UDim2.new(0.8, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
		label.BackgroundTransparency = 0.05
		label.TextColor3 = Color3.fromRGB(255, 130, 130)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 17
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		local padding = Instance.new("UIPadding")
		local pad = UDim.new(0, 14)
		padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = pad, pad, pad, pad
		padding.Parent = label
		label.Parent = gui
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		notice = label
	end
	if notice then
		notice.Text = table.concat(lines, "\n")
	end
end

local function problem(text: string)
	warn(("%s ✗ %s"):format(TAG, text))
	table.insert(problems, text)
end

ReplicatedStorage:GetAttributeChangedSignal(SERVER_PROBLEM):Connect(showProblems)

-- 1. Load every module (a broken one is reported instead of stopping the rest)
local requireModule: any = require -- the modules are found at run time
local loaded: { [string]: any } = {}
for _, entry in MODULES do
	local module = entry.Parent:WaitForChild(entry.Name, 10)
	if not module or not module:IsA("ModuleScript") then
		problem(("Missing ModuleScript %s (paste scripts/%s.luau into it)."):format(entry.Where, entry.File))
		continue
	end
	local ok, result = pcall(requireModule, module)
	if not ok then
		problem(("%s failed to load: %s. Paste scripts/%s.luau into %s again."):format(entry.Name, tostring(result), entry.File, entry.Where))
		continue
	end
	loaded[entry.Name] = result
	-- 2. Is it an old copy?
	local actual = if typeof(result) == "table" and typeof(result.ScriptVersion) == "number" then result.ScriptVersion else 1
	if actual < entry.Version then
		problem(("%s is an old copy (version %d, needs %d). Paste scripts/%s.luau into %s again."):format(entry.Name, actual, entry.Version, entry.File, entry.Where))
	elseif actual > entry.Version then
		problem(("%s is newer than this ClientMain expects, so ClientMain is the old copy. Paste scripts/13_Client_ClientMain.luau into StarterPlayer > StarterPlayerScripts > ClientMain again."):format(entry.Name))
	end
end
showProblems()

-- 3. Start them. One that errors, or waits forever for something the server
-- never made, is reported and the rest still start.
for _, name in START_ORDER do
	local module = loaded[name]
	if not module or typeof(module.Init) ~= "function" then
		continue
	end
	local finished = false
	local failure: string? = nil
	task.spawn(function()
		local ok, err = pcall(module.Init)
		finished = true
		if not ok then
			failure = tostring(err)
		end
	end)
	local waited = 0
	while not finished and waited < 10 and not serverProblem() do
		waited += task.wait()
	end
	if failure and serverProblem() then
		-- Most likely a knock-on effect of the server's problem: Output only
		warn(("%s ✗ %s failed to start: %s"):format(TAG, name, failure))
	elseif failure then
		problem(("%s failed to start: %s"):format(name, failure))
	elseif not finished and not serverProblem() then
		problem(("%s is still waiting after 10 seconds for something the server creates. Check the server's [Street Hoops] lines in Output."):format(name))
	end
	showProblems()
end

if #problems == 0 and not serverProblem() then
	print(("%s ✓ Client ready"):format(TAG))
end
