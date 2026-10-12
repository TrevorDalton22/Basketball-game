--!strict
-- Main (Script) — ServerScriptService > Server > Main
-- Server entry point: builds the world, starts every service in order, and
-- runs the single Heartbeat loop that drives them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Server = script.Parent
local CharacterService = require(Server:WaitForChild("CharacterService"))
local CourtBuilder = require(Server:WaitForChild("CourtBuilder"))
local BallService = require(Server:WaitForChild("BallService"))
local MatchService = require(Server:WaitForChild("MatchService"))
local QueueService = require(Server:WaitForChild("QueueService"))
local ShotService = require(Server:WaitForChild("ShotService"))

-- Remotes must exist before any client script asks for them
Net.CreateAll()
CharacterService.Init()

local courts = CourtBuilder.Build()
MatchService.Init(courts)
QueueService.Init()
ShotService.Init()

local function step(name: string, fn: (number) -> (), dt: number)
	local ok, err = pcall(function()
		fn(dt)
	end)
	if not ok then
		warn(("[Main] %s.Update error: %s"):format(name, tostring(err)))
	end
end

RunService.Heartbeat:Connect(function(dt)
	step("CharacterService", CharacterService.Update, dt)
	step("BallService", BallService.Update, dt)
	step("MatchService", MatchService.Update, dt)
	step("QueueService", QueueService.Update, dt)
end)

print(("[Main] Street Hoops server ready — %d court(s)"):format(#courts))
