--!strict
-- MatchClient (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > MatchClient
-- Read-only view of the server's court attributes. Works out which court the
-- local player is queued on or playing on, and which ball they hold.
-- Nothing here decides gameplay; it only reads what the server published.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BasketballMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BasketballMath"))

local MatchClient = {}

local player = Players.LocalPlayer

-- Fires whenever any court or ball attribute changes
MatchClient.Changed = Signal.new()

local courts: { Model } = {}

export type Role = "Playing" | "Queued" | "None"

local function watchCourt(model: Model)
	if table.find(courts, model) then
		return
	end
	table.insert(courts, model)
	model.AttributeChanged:Connect(function()
		MatchClient.Changed:Fire()
	end)
	local function watchBall(child: Instance)
		if child.Name == "Ball" and child:IsA("BasePart") then
			child.AttributeChanged:Connect(function()
				MatchClient.Changed:Fire()
			end)
			MatchClient.Changed:Fire()
		end
	end
	model.ChildAdded:Connect(watchBall)
	for _, child in model:GetChildren() do
		watchBall(child)
	end
	MatchClient.Changed:Fire()
end

function MatchClient.Init()
	task.spawn(function()
		local folder = workspace:WaitForChild("Courts")
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				watchCourt(child)
			end
		end)
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				watchCourt(child)
			end
		end
	end)
end

function MatchClient.GetCourts(): { Model }
	return courts
end

function MatchClient.GetBall(court: Model): BasePart?
	local ball = court:FindFirstChild("Ball")
	if ball and ball:IsA("BasePart") then
		return ball
	end
	return nil
end

-- The court the local player is playing on or queued for, their role and side
function MatchClient.GetMyCourt(): (Model?, Role, string?)
	local id = player.UserId
	for _, court in courts do
		if court.Parent == nil then
			continue
		end
		if court:GetAttribute("HomeUserId") == id then
			return court, "Playing", "Home"
		elseif court:GetAttribute("AwayUserId") == id then
			return court, "Playing", "Away"
		end
	end
	for _, court in courts do
		if court.Parent == nil then
			continue
		end
		if court:GetAttribute("PadHomeUserId") == id then
			return court, "Queued", "Home"
		elseif court:GetAttribute("PadAwayUserId") == id then
			return court, "Queued", "Away"
		end
	end
	return nil, "None", nil
end

-- The ball the local player is holding, if any (server-set attribute)
function MatchClient.GetHeldBall(): (BasePart?, Model?)
	for _, court in courts do
		local ball = MatchClient.GetBall(court)
		if ball and ball:GetAttribute("HolderUserId") == player.UserId then
			return ball, court
		end
	end
	return nil, nil
end

-- Mirrors the server's rule closely enough to show/hide the shoot controls.
-- The server still validates every shot.
function MatchClient.CanShootNow(): boolean
	local ball, court = MatchClient.GetHeldBall()
	if not ball or not court then
		return false
	end
	local state = court:GetAttribute("State")
	if state == "Live" then
		local id = player.UserId
		return court:GetAttribute("HomeUserId") == id or court:GetAttribute("AwayUserId") == id
	end
	return state == "Idle"
end

local function courtOrigin(court: Model): CFrame?
	local id = court:GetAttribute("CourtId")
	for _, def in Config.Courts do
		if def.Id == id then
			return BasketballMath.CourtOrigin(def.Position, def.Yaw)
		end
	end
	return nil
end

-- If we're driving at the rim with the ball: "Dunk" or "Layup" (and the rim
-- centre). A touch stricter than the server's check so the two agree.
function MatchClient.PredictFinish(): (string?, Vector3?)
	local ball, court = MatchClient.GetHeldBall()
	if not ball or not court then
		return nil, nil
	end
	local rim = court:GetAttribute("RimCenter")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if typeof(rim) ~= "Vector3" or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	-- The server refuses finishes from the strip behind the backboard
	local origin = courtOrigin(court)
	if origin then
		local localPos = origin:PointToObjectSpace(root.Position)
		local boardHalf = Config.Court.BackboardSize.X / 2 + 3.5
		if localPos.Z < Config.Court.BackboardZ + 0.3 and math.abs(localPos.X) <= boardHalf then
			return nil, nil
		end
	end
	local offset = Vector3.new(rim.X - root.Position.X, 0, rim.Z - root.Position.Z)
	local distance = offset.Magnitude
	if distance < 1e-3 then
		return nil, nil
	end
	local v = root.AssemblyLinearVelocity
	local approach = Vector3.new(v.X, 0, v.Z):Dot(offset.Unit)
	-- The server sees us a little later (further out) than we see ourselves; it
	-- allows for about 0.1 s of that, this covers some extra on slow connections
	local judged = distance + math.max(approach, 0) * 0.05
	local finish = Config.Finish
	if judged <= finish.DunkRange - 0.3 and approach >= finish.DunkMinApproach + 1 then
		return "Dunk", rim
	elseif judged <= finish.LayupRange - 0.3 and approach >= finish.LayupMinApproach + 1 then
		return "Layup", rim
	end
	return nil, nil
end

-- True when we're in a live match and our opponent has the ball (we can steal).
-- The server still validates every steal.
function MatchClient.CanStealNow(): boolean
	local court, role = MatchClient.GetMyCourt()
	if not court or role ~= "Playing" or court:GetAttribute("State") ~= "Live" then
		return false
	end
	local ball = MatchClient.GetBall(court)
	local holder = if ball then ball:GetAttribute("HolderUserId") else 0
	return typeof(holder) == "number" and holder ~= 0 and holder ~= player.UserId
end

return MatchClient
