--!strict
-- QueueService (ModuleScript) — ServerScriptService > Server > QueueService
-- Each court has a Home and an Away pad. Standing on a pad claims it; stepping
-- off (or pressing Leave) releases it. When both pads are claimed on an open
-- court, a short delay runs and then MatchService starts the 1v1.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Server = script.Parent
local CharacterService = require(Server:WaitForChild("CharacterService"))
local MatchService = require(Server:WaitForChild("MatchService"))
local RemoteGuard = require(Server:WaitForChild("RemoteGuard"))

local QueueService = {}

local QUEUE = Config.Queue
local SIDES = { "Home", "Away" }

type Queue = {
	CourtState: any, -- MatchService.CourtState
	Claims: { [string]: Player? },
	ReadyAt: number, -- 0 when not counting down
	LastVisual: string,
}

local queues: { Queue } = {}
local cooldownUntil: { [Player]: number } = {}
local pollTimer = 0

local function isStandingOn(pad: BasePart, root: BasePart): boolean
	local localPos = pad.CFrame:PointToObjectSpace(root.Position)
	local half = QUEUE.PadSize / 2 + 0.5
	-- Generous height range so hopping on the pad never drops the claim
	local maxHeight = Config.Movement.JumpHeight + 8
	return math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half and localPos.Y > -1 and localPos.Y < maxHeight
end

local function claimOf(player: Player): (Queue?, string?)
	for _, queue in queues do
		for _, side in SIDES do
			if queue.Claims[side] == player then
				return queue, side
			end
		end
	end
	return nil, nil
end

local function publish(queue: Queue)
	local cs = queue.CourtState
	local court = cs.Court
	local model: Model = court.Model
	local home = queue.Claims.Home
	local away = queue.Claims.Away
	local function setAttr(name: string, value: any)
		if model:GetAttribute(name) ~= value then
			model:SetAttribute(name, value)
		end
	end
	setAttr("PadHomeUserId", if home then home.UserId else 0)
	setAttr("PadAwayUserId", if away then away.UserId else 0)
	setAttr("QueueReadyAt", queue.ReadyAt)

	-- Pad visuals, only touched when something changed
	local locked = cs.State ~= "Idle"
	local visualKey = ("%s|%d|%d"):format(tostring(locked), if home then home.UserId else 0, if away then away.UserId else 0)
	if visualKey == queue.LastVisual then
		return
	end
	queue.LastVisual = visualKey
	for _, side in SIDES do
		local pad: BasePart = court.Pads[side]
		local label: TextLabel = court.PadLabels[side]
		local claimant = queue.Claims[side]
		local teamColor = if side == "Home" then Config.UI.Home else Config.UI.Away
		if locked then
			pad.Color = Color3.fromRGB(90, 94, 104)
			pad.Transparency = 0.5
			label.Text = "IN GAME"
		elseif claimant then
			pad.Color = teamColor
			pad.Transparency = 0
			label.Text = claimant.DisplayName
		else
			pad.Color = teamColor
			pad.Transparency = 0.15
			label.Text = (if side == "Home" then "HOME" else "AWAY") .. " · 1V1"
		end
	end
end

local function release(queue: Queue, side: string)
	queue.Claims[side] = nil
	queue.ReadyAt = 0
end

local function pollQueue(queue: Queue, t: number)
	local cs = queue.CourtState
	local court = cs.Court
	if cs.State ~= "Idle" then
		if queue.Claims.Home or queue.Claims.Away or queue.ReadyAt ~= 0 then
			queue.Claims.Home = nil
			queue.Claims.Away = nil
			queue.ReadyAt = 0
		end
		publish(queue)
		return
	end

	-- Drop claims that are no longer valid
	for _, side in SIDES do
		local claimant = queue.Claims[side]
		if claimant then
			local root = CharacterService.GetRoot(claimant)
			if not claimant.Parent or not root or MatchService.IsInMatch(claimant) or not isStandingOn(court.Pads[side], root) then
				release(queue, side)
			end
		end
	end

	-- Fill empty pads with whoever is standing on them
	for _, side in SIDES do
		if queue.Claims[side] then
			continue
		end
		for _, player in Players:GetPlayers() do
			local blocked = cooldownUntil[player]
			if (blocked and blocked > t) or MatchService.IsInMatch(player) or claimOf(player) then
				continue
			end
			local root = CharacterService.GetRoot(player)
			if root and isStandingOn(court.Pads[side], root) then
				queue.Claims[side] = player
				queue.ReadyAt = 0
				break
			end
		end
	end

	local home, away = queue.Claims.Home, queue.Claims.Away
	if home and away then
		if queue.ReadyAt == 0 then
			queue.ReadyAt = workspace:GetServerTimeNow() + QUEUE.StartDelay
		elseif workspace:GetServerTimeNow() >= queue.ReadyAt then
			queue.Claims.Home = nil
			queue.Claims.Away = nil
			queue.ReadyAt = 0
			MatchService.StartMatch(cs, home, away)
		end
	else
		queue.ReadyAt = 0
	end
	publish(queue)
end

local function onLeaveQueue(player: Player)
	if not RemoteGuard.Allow(player) then
		return
	end
	local queue, side = claimOf(player)
	if not queue or not side then
		return
	end
	release(queue, side)
	cooldownUntil[player] = os.clock() + QUEUE.ReclaimCooldown
	-- Step them off the pad so they do not re-claim it when the cooldown ends
	CharacterService.Teleport(player, queue.CourtState.Court.ReturnSpots[side])
	publish(queue)
end

function QueueService.Init()
	for _, cs in MatchService.GetCourtStates() do
		local queue: Queue = { CourtState = cs, Claims = {}, ReadyAt = 0, LastVisual = "" }
		table.insert(queues, queue)
		publish(queue)
	end
	Net.Event("LeaveQueue").OnServerEvent:Connect(onLeaveQueue)
	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player] = nil
		local queue, side = claimOf(player)
		if queue and side then
			release(queue, side)
			publish(queue)
		end
	end)
end

function QueueService.Update(dt: number)
	pollTimer += dt
	if pollTimer < QUEUE.PollInterval then
		return
	end
	pollTimer = 0
	local t = os.clock()
	for _, queue in queues do
		pollQueue(queue, t)
	end
end

return QueueService
