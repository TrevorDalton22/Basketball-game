--!strict
-- ClientMain (LocalScript) — StarterPlayer > StarterPlayerScripts > ClientMain
-- Client entry point. Its children are the client modules; this script only
-- starts them in the right order.

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
