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

MatchClient.Init()
Hud.Init()
ShotMeter.Init()
ShootController.Init()
BallVisuals.Init()
