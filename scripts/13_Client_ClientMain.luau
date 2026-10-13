--!strict
-- ClientMain (LocalScript) — StarterPlayer > StarterPlayerScripts > ClientMain
-- Client entry point. Its children are the client modules; this script only
-- starts them in the right order.

-- Pasted into the wrong script? Say so instead of waiting forever.
if game:GetService("RunService"):IsServer() then
	warn(("[Street Hoops] ✗ %s contains the ClientMain code (scripts/13_Client_ClientMain.luau). Paste that code into the ClientMain LocalScript, and put scripts/05_Server_Main.luau in ServerScriptService > Server > Main."):format(script:GetFullName()))
	return
end

local Client = script

local MatchClient = require(Client:WaitForChild("MatchClient"))
local Hud = require(Client:WaitForChild("Hud"))
local ShotMeter = require(Client:WaitForChild("ShotMeter"))
local ShootController = require(Client:WaitForChild("ShootController"))
local BallVisuals = require(Client:WaitForChild("BallVisuals"))
local MovesController = require(Client:WaitForChild("MovesController"))

MatchClient.Init()
Hud.Init()
ShotMeter.Init()
ShootController.Init()
MovesController.Init() -- after ShootController so steal/crossover keys take priority when they apply
BallVisuals.Init()
