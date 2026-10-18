--!strict
-- Main (Script) — ServerScriptService > Server > Main
-- Server entry point. First checks that every script from the README is in
-- the right place with the right type (and says exactly what to fix if not),
-- then builds the world, starts every service in order, and runs the single
-- Heartbeat loop that drives them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TAG = "[Street Hoops]"

-- Pasted into the wrong script? Say so instead of misbehaving.
if RunService:IsClient() then
	warn(("%s ✗ %s contains the server Main code (scripts/05_Server_Main.luau). It belongs in the Script at ServerScriptService > Server > Main; this LocalScript needs scripts/13_Client_ClientMain.luau."):format(TAG, script:GetFullName()))
	return
end

-- This file's version, published first so ClientMain can tell when Main is the
-- old copy, and the version ClientMain must check in with (see the end)
local MAIN_VERSION = 6
local CLIENT_MAIN_VERSION = 6
ReplicatedStorage:SetAttribute("StreetHoopsMainVersion", MAIN_VERSION)

--------------------------------------------------------------------------------
-- 1. Setup check: every script the README creates, where it must live
--------------------------------------------------------------------------------

-- Version: the ScriptVersion each shared/server module must report (a module
-- without one counts as 1). ClientMain checks the client modules the same way.
type Expected = { Path: { string }, Class: string, File: string?, Version: number? }

local EXPECTED: { Expected } = {
	{ Path = { "ReplicatedStorage", "Shared" }, Class = "Folder" },
	{ Path = { "ReplicatedStorage", "Shared", "Config" }, Class = "ModuleScript", File = "01_Shared_Config", Version = 4 },
	{ Path = { "ReplicatedStorage", "Shared", "Signal" }, Class = "ModuleScript", File = "02_Shared_Signal", Version = 1 },
	{ Path = { "ReplicatedStorage", "Shared", "Net" }, Class = "ModuleScript", File = "03_Shared_Net", Version = 3 },
	{ Path = { "ReplicatedStorage", "Shared", "BasketballMath" }, Class = "ModuleScript", File = "04_Shared_BasketballMath", Version = 1 },
	{ Path = { "ServerScriptService", "Server" }, Class = "Folder" },
	{ Path = { "ServerScriptService", "Server", "Main" }, Class = "Script", File = "05_Server_Main" },
	{ Path = { "ServerScriptService", "Server", "CharacterService" }, Class = "ModuleScript", File = "06_Server_CharacterService", Version = 3 },
	{ Path = { "ServerScriptService", "Server", "RemoteGuard" }, Class = "ModuleScript", File = "07_Server_RemoteGuard", Version = 1 },
	{ Path = { "ServerScriptService", "Server", "CourtBuilder" }, Class = "ModuleScript", File = "08_Server_CourtBuilder", Version = 3 },
	{ Path = { "ServerScriptService", "Server", "BallService" }, Class = "ModuleScript", File = "09_Server_BallService", Version = 2 },
	{ Path = { "ServerScriptService", "Server", "MatchService" }, Class = "ModuleScript", File = "10_Server_MatchService", Version = 4 },
	{ Path = { "ServerScriptService", "Server", "QueueService" }, Class = "ModuleScript", File = "11_Server_QueueService", Version = 2 },
	{ Path = { "ServerScriptService", "Server", "ShotService" }, Class = "ModuleScript", File = "12_Server_ShotService", Version = 3 },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain" }, Class = "LocalScript", File = "13_Client_ClientMain" },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain", "UIKit" }, Class = "ModuleScript", File = "14_Client_UIKit" },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain", "MatchClient" }, Class = "ModuleScript", File = "15_Client_MatchClient" },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain", "ShotMeter" }, Class = "ModuleScript", File = "16_Client_ShotMeter" },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain", "ShootController" }, Class = "ModuleScript", File = "17_Client_ShootController" },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain", "BallVisuals" }, Class = "ModuleScript", File = "18_Client_BallVisuals" },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain", "Hud" }, Class = "ModuleScript", File = "19_Client_Hud" },
	{ Path = { "ServerScriptService", "Server", "MovesService" }, Class = "ModuleScript", File = "20_Server_MovesService", Version = 1 },
	{ Path = { "StarterPlayer", "StarterPlayerScripts", "ClientMain", "MovesController" }, Class = "ModuleScript", File = "21_Client_MovesController" },
	{ Path = { "ServerScriptService", "Server", "DataService" }, Class = "ModuleScript", File = "22_Server_DataService", Version = 2 },
	{ Path = { "ServerScriptService", "Server", "ProgressionService" }, Class = "ModuleScript", File = "23_Server_ProgressionService", Version = 2 },
}

local SEARCH_ROOTS = { "Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui", "StarterPack", "Lighting" }

local function pathText(path: { string }): string
	return table.concat(path, " > ")
end

local function resolve(path: { string }): Instance?
	local current: Instance? = game:GetService(path[1] :: any)
	for i = 2, #path do
		if not current then
			return nil
		end
		current = current:FindFirstChild(path[i])
	end
	return current
end

-- Find objects with this name elsewhere (any capitalisation), to say where it went
local function findElsewhere(name: string): { Instance }
	local found = {}
	local lower = name:lower()
	for _, rootName in SEARCH_ROOTS do
		local ok, root = pcall(function()
			return game:GetService(rootName :: any)
		end)
		if ok and root then
			for _, descendant in root:GetDescendants() do
				if descendant.Name:lower() == lower and (descendant:IsA("LuaSourceContainer") or descendant:IsA("Folder")) then
					table.insert(found, descendant)
				end
			end
		end
	end
	return found
end

local function checkSetup(): { string }
	local problems = {}
	for _, item in EXPECTED do
		local name = item.Path[#item.Path]
		local instance = resolve(item.Path)
		local fileHint = if item.File then (" (paste scripts/%s.luau)"):format(item.File) else ""
		if not instance then
			local elsewhere = findElsewhere(name)
			if #elsewhere > 0 then
				local spots = {}
				for _, other in elsewhere do
					table.insert(spots, ("%s [%s]"):format(other:GetFullName(), other.ClassName))
				end
				table.insert(problems, ("%s is not where it should be. Found: %s. Move it to %s and check the spelling/capitals."):format(name, table.concat(spots, ", "), pathText(item.Path)))
			else
				table.insert(problems, ("Missing %s '%s' at %s%s."):format(item.Class, name, pathText(item.Path), fileHint))
			end
		elseif instance.ClassName ~= item.Class then
			table.insert(problems, ("%s is a %s but must be a %s. Delete it, insert a %s with the same name in the same place, and paste the code again%s."):format(pathText(item.Path), instance.ClassName, item.Class, item.Class, fileHint))
		end
	end
	return problems
end

--------------------------------------------------------------------------------
-- 2. Safety floor: if anything goes wrong, players stand on something and see
--    a sign instead of falling forever
--------------------------------------------------------------------------------

local function buildSafetyFloor(message: string)
	if workspace:FindFirstChild("StreetHoopsSafetyFloor") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "StreetHoopsSafetyFloor"
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(200, 2, 200)
	floor.CFrame = CFrame.new(0, -1, 0)
	floor.Color = Color3.fromRGB(90, 90, 96)
	floor.Material = Enum.Material.Concrete
	floor.Parent = folder
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SafetySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	local board = Instance.new("Part")
	board.Name = "SetupProblemSign"
	board.Anchored = true
	board.Size = Vector3.new(24, 9, 0.5)
	board.CFrame = CFrame.lookAt(Vector3.new(0, 6, -14), Vector3.new(0, 6, 0))
	board.Color = Color3.fromRGB(20, 22, 30)
	board.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 120, 120)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "STREET HOOPS SETUP PROBLEM\n" .. message .. "\nOpen View > Output for details"
	label.Parent = gui
	folder.Parent = workspace
end

-- Players who spawned before the map existed (and are falling) get respawned
-- onto it. With `everyone`, every spawned character is moved to the new spawn.
local function respawnFallenPlayers(everyone: boolean)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue -- not spawned yet: they will spawn on the new SpawnLocation
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local falling = not root or not root:IsA("BasePart") or root.Position.Y < -5
		if everyone or falling then
			task.spawn(function()
				player:LoadCharacter()
			end)
		end
	end
end

local function fail(summary: string, details: { string })
	warn(("%s ✗ %s"):format(TAG, summary))
	for i, line in details do
		warn(("%s   %d. %s"):format(TAG, i, line))
	end
	-- Players show this on screen too (Output is easy to miss)
	ReplicatedStorage:SetAttribute("StreetHoopsSetupProblem", summary .. "\n" .. table.concat(details, "\n"))
	warn(("%s Fix the items above, then press Play again. (README → Step 4 has the full tree.)"):format(TAG))
	buildSafetyFloor(summary)
	respawnFallenPlayers(true)
end

--------------------------------------------------------------------------------
-- 3. Start-up
--------------------------------------------------------------------------------

local problems = checkSetup()
if #problems > 0 then
	fail(("%d setup problem(s) found"):format(#problems), problems)
	return
end
print(("%s ✓ All %d scripts found in the right places"):format(TAG, #EXPECTED - 2))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent

local expectedByName: { [string]: Expected } = {}
for _, item in EXPECTED do
	expectedByName[item.Path[#item.Path]] = item
end

-- Does this loaded module hold the right file's code, in the current version?
-- (An old copy of one file, not re-pasted after an update, is the usual reason
-- a feature quietly stops working, so name the exact file to paste again.)
local function moduleProblem(name: string, module: any): string?
	local item = expectedByName[name]
	if not item or item.Version == nil then
		return nil
	end
	local file = if typeof(module) == "table" then module.ScriptFile else nil
	if typeof(file) == "string" and file ~= item.File then
		return ("%s holds the code from scripts/%s.luau. Paste scripts/%s.luau into %s instead."):format(name, file, item.File or name, pathText(item.Path))
	end
	local actual = if typeof(module) == "table" and typeof(module.ScriptVersion) == "number" then module.ScriptVersion else 1
	if actual < item.Version then
		return ("%s is an old copy (version %d, needs %d). Paste scripts/%s.luau into %s again."):format(name, actual, item.Version, item.File or name, pathText(item.Path))
	elseif actual > item.Version then
		return ("%s is newer than this Main expects, so Main is the old copy. Paste scripts/05_Server_Main.luau into ServerScriptService > Server > Main again."):format(name)
	end
	return nil
end

-- Each module is checked as soon as it loads, so a wrong one is named even when
-- a module after it then fails because of it
local LOAD_TIME = 5 -- correct modules load instantly (everything they wait for exists)
local loaded: { [string]: any } = {}
local stale: { string } = {}
local function load(parent: Instance, name: string): boolean
	local module = parent:FindFirstChild(name)
	local item = expectedByName[name]
	local file = if item and item.File then item.File else name
	local where = if item then pathText(item.Path) else name
	-- (dynamic require: the module was located by the setup check above)
	local requireModule: any = require
	-- Load on a separate thread, so code that waits forever can't stall start-up
	local finished, ok, result = false, false, nil
	task.spawn(function()
		ok, result = pcall(function()
			return requireModule(module)
		end)
		finished = true
	end)
	local deadline = os.clock() + LOAD_TIME
	while not finished and os.clock() < deadline do
		task.wait()
	end
	local failure: string? = nil
	if not finished then
		failure = ("%s is still loading after %d seconds: it waits for something that doesn't exist, so it probably holds another file's code. Paste scripts/%s.luau into %s again."):format(name, LOAD_TIME, file, where)
	elseif not ok then
		failure = ("%s failed to load: %s. Paste scripts/%s.luau into %s again (in the script: Ctrl+A, then Ctrl+V)."):format(name, tostring(result), file, where)
	elseif result == nil then
		failure = ("%s doesn't return anything, so the paste was probably cut off. Paste all of scripts/%s.luau into %s again."):format(name, file, where)
	end
	if failure then
		-- Problems already found in earlier modules are often the cause: list them first
		local details = table.clone(stale)
		table.insert(details, failure)
		fail(("%d script problem(s) found"):format(#details), details)
		return false
	end
	loaded[name] = result
	local problem = moduleProblem(name, result)
	if problem then
		table.insert(stale, problem)
	end
	return true
end

for _, name in { "Config", "Signal", "Net", "BasketballMath" } do
	if not load(Shared, name) then
		return
	end
end
for _, name in { "CharacterService", "RemoteGuard", "CourtBuilder", "BallService", "MatchService", "QueueService", "ShotService", "MovesService", "DataService", "ProgressionService" } do
	if not load(Server, name) then
		return
	end
end
if #stale > 0 then
	fail(("%d script(s) are out of date or hold the wrong code"):format(#stale), stale)
	return
end
print(("%s ✓ Shared and server scripts are up to date (ClientMain checks the client ones)"):format(TAG))

local Net = loaded.Net
local CharacterService = loaded.CharacterService
local CourtBuilder = loaded.CourtBuilder
local BallService = loaded.BallService
local MatchService = loaded.MatchService
local QueueService = loaded.QueueService
local ShotService = loaded.ShotService
local MovesService = loaded.MovesService
local DataService = loaded.DataService
local ProgressionService = loaded.ProgressionService

local courts: { any } = {}
local function startStep(name: string, fn: () -> ()): boolean
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		fail(("Start-up step '%s' failed"):format(name), { tostring(err) })
		return false
	end
	return true
end

local steps: { { Name: string, Run: () -> () } } = {
	-- Remotes must exist before any client script asks for them
	{ Name = "Create remotes", Run = function()
		Net.CreateAll()
	end },
	{ Name = "Player data", Run = function()
		DataService.Init()
	end },
	{ Name = "Characters", Run = function()
		CharacterService.Init()
	end },
	{ Name = "Build the park and courts", Run = function()
		courts = CourtBuilder.Build()
	end },
	{ Name = "Matches", Run = function()
		MatchService.Init(courts)
	end },
	{ Name = "Queues", Run = function()
		QueueService.Init()
	end },
	{ Name = "Shooting", Run = function()
		ShotService.Init()
	end },
	{ Name = "Steals and moves", Run = function()
		MovesService.Init()
	end },
	{ Name = "Progression", Run = function()
		ProgressionService.Init()
	end },
}
for _, entry in steps do
	if not startStep(entry.Name, entry.Run) then
		return
	end
end

-- Anyone who spawned before the map finished building lands on it now
respawnFallenPlayers(false)


local function step(name: string, fn: (number) -> (), dt: number)
	local ok, err = pcall(function()
		fn(dt)
	end)
	if not ok then
		warn(("%s %s.Update error: %s"):format(TAG, name, tostring(err)))
	end
end

RunService.Heartbeat:Connect(function(dt)
	step("CharacterService", CharacterService.Update, dt)
	step("BallService", BallService.Update, dt)
	step("MatchService", MatchService.Update, dt)
	step("QueueService", QueueService.Update, dt)
end)

print(("%s ✓ Server ready — %d court(s)"):format(TAG, #courts))

-- An old ClientMain can't report itself, so every current one checks in (set
-- up last, after the game loop, so nothing here can hold the game up). A
-- player whose client never does is told (in Output and on their screen).
-- Longer on a live server, where a slow phone can take a while to load
local CHECK_IN_TIME = if RunService:IsStudio() then 30 else 90
local checkedIn: { [Player]: boolean } = {}
local clientNotices: { [Player]: ScreenGui } = {}
local warnedLate: { [Player]: boolean } = {}

local function showClientNotice(player: Player, text: string)
	warn(("%s ✗ %s: %s"):format(TAG, player.Name, text))
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui or clientNotices[player] then
		return
	end
	-- Made by the server, so it shows even when the player's ClientMain is old
	local gui = Instance.new("ScreenGui")
	gui.Name = "StreetHoopsClientProblem"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 70)
	label.Size = UDim2.new(0.8, 0, 0, 90)
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	label.BackgroundTransparency = 0.05
	label.TextColor3 = Color3.fromRGB(255, 130, 130)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 17
	label.TextWrapped = true
	label.Text = "STREET HOOPS SETUP PROBLEM\n" .. text
	label.Parent = gui
	gui.Parent = playerGui
	clientNotices[player] = gui
end

Net.Event("ClientReady").OnServerEvent:Connect(function(player: Player, version: any)
	if checkedIn[player] then
		return
	end
	checkedIn[player] = true
	local notice = clientNotices[player]
	if notice then
		notice:Destroy()
		clientNotices[player] = nil
	end
	if warnedLate[player] then
		warnedLate[player] = nil
		print(("%s ✓ %s: ClientMain checked in after all (it was only slow to load), so ignore the ✗ above."):format(TAG, player.Name))
	end
	if typeof(version) == "number" and version < CLIENT_MAIN_VERSION then
		showClientNotice(player, "ClientMain is an old copy. Paste scripts/13_Client_ClientMain.luau into StarterPlayer > StarterPlayerScripts > ClientMain again.")
	end
end)

local function watchClient(player: Player)
	task.delay(CHECK_IN_TIME, function()
		if player.Parent and not checkedIn[player] then
			warnedLate[player] = true
			local clientMain = resolve({ "StarterPlayer", "StarterPlayerScripts", "ClientMain" })
			if clientMain and clientMain:IsA("LocalScript") and not clientMain.Enabled then
				showClientNotice(player, "ClientMain is disabled. Select StarterPlayer > StarterPlayerScripts > ClientMain and tick Enabled in Properties.")
			else
				showClientNotice(player, "ClientMain didn't start, or is an old copy. Paste scripts/13_Client_ClientMain.luau into the LocalScript StarterPlayer > StarterPlayerScripts > ClientMain again.")
			end
		end
	end)
end
Players.PlayerAdded:Connect(watchClient)
for _, player in Players:GetPlayers() do
	watchClient(player)
end
Players.PlayerRemoving:Connect(function(player)
	checkedIn[player] = nil
	clientNotices[player] = nil
	warnedLate[player] = nil
end)
