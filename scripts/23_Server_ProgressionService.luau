--!strict
-- ProgressionService (ModuleScript) — ServerScriptService > Server > ProgressionService
-- Turns finished matches into stats and coins. Every reward is decided here,
-- on the server, from the match result; clients only display them. Shows the
-- stats in the player list (leaderstats) and on player attributes for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Server = script.Parent
local DataService = require(Server:WaitForChild("DataService"))
local MatchService = require(Server:WaitForChild("MatchService"))

local ProgressionService = {}
ProgressionService.ScriptVersion = 2 -- Main compares this to spot an old copy; bump when this file changes
ProgressionService.ScriptFile = "23_Server_ProgressionService" -- and this to spot another file's code pasted here

local PROGRESSION = Config.Progression
local LEADERSTATS = { "Wins", "Coins" } -- shown in the Roblox player list

-- How each way of ending a match is treated
local COUNTS: { [string]: boolean } = {
	Score = true,
	Time = true,
	Overtime = true,
	Draw = true,
	Forfeit = true, -- unless it happens straight away (see MinPlayedSeconds)
	Cancelled = false,
}

local feedback: RemoteEvent
local toldNotSaved: { [Player]: boolean } = {}

-- Player list + attributes (the HUD reads the attributes)
local function show(player: Player)
	local stats = DataService.GetStats(player)
	if not stats or not player.Parent then
		return
	end
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "leaderstats"
		newFolder.Parent = player
		folder = newFolder
	end
	for _, name in LEADERSTATS do
		local value = (folder :: Instance):FindFirstChild(name)
		if not value then
			local newValue = Instance.new("IntValue")
			newValue.Name = name
			newValue.Parent = folder
			value = newValue
		end
		if value and value:IsA("IntValue") then
			value.Value = stats[name] or 0
		end
	end
	for name, amount in stats do
		player:SetAttribute(name, amount)
	end
	local status = DataService.GetStatus(player)
	player:SetAttribute("StatsStatus", status)
	if status == "SessionOnly" and not toldNotSaved[player] then
		toldNotSaved[player] = true
		feedback:FireClient(player, "Notice", { Text = "Your stats aren't being saved this session (the server's Output says why)" })
	end
end

local function onMatchEnded(result: MatchService.MatchResult)
	local reason = result.Reason
	local counts = COUNTS[reason] == true and (reason ~= "Forfeit" or result.Played >= PROGRESSION.MinPlayedSeconds)
	local rewards = PROGRESSION.Rewards
	for _, side in { "Home", "Away" } do
		local player = if side == "Home" then result.Home else result.Away
		if not player then
			continue
		end
		if not counts then
			if player.Parent then
				local note = if reason == "Cancelled"
					then "Cancelled matches don't count"
					else ("Matches that end in the first %d seconds don't count"):format(PROGRESSION.MinPlayedSeconds)
				feedback:FireClient(player, "Rewards", { Counted = false, Note = note })
			end
			continue
		end
		local score = if side == "Home" then result.HomeScore else result.AwayScore
		local outcome = if result.Winner == player then "Win" elseif result.Winner == nil then "Draw" else "Loss"
		-- Shorter games (a lower target) pay proportionally less
		local scale = result.TargetScore / Config.Match.TargetScore
		local coins = math.floor(rewards[outcome] * scale + 0.5) + math.min(score * rewards.PerPoint, rewards.MaxPointCoins)
		if reason == "Forfeit" and outcome == "Loss" then
			coins = 0 -- quitting still counts as a loss, but earns nothing
		end
		DataService.Increment(player, if outcome == "Win" then "Wins" elseif outcome == "Loss" then "Losses" else "Draws", 1)
		DataService.Increment(player, "Games", 1)
		DataService.Increment(player, "Points", score)
		DataService.Increment(player, "Coins", coins)
		local stats = DataService.GetStats(player)
		if player.Parent and stats then
			feedback:FireClient(player, "Rewards", {
				Counted = true,
				Outcome = outcome,
				Coins = coins,
				Wins = stats.Wins,
				Losses = stats.Losses,
				Draws = stats.Draws,
				TotalCoins = stats.Coins,
				Saved = DataService.GetStatus(player) ~= "SessionOnly",
			})
		end
	end
end

function ProgressionService.Init()
	feedback = Net.Event("Feedback")
	DataService.Changed:Connect(show)
	for _, player in Players:GetPlayers() do
		show(player)
	end
	MatchService.MatchEnded:Connect(onMatchEnded)
	Players.PlayerRemoving:Connect(function(player)
		toldNotSaved[player] = nil
	end)
end

return ProgressionService
