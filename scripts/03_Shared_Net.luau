--!strict
-- Net (ModuleScript) — ReplicatedStorage > Shared > Net
-- One place that names every remote. The server creates them on startup;
-- clients wait for them. Never create remotes anywhere else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}
Net.ScriptVersion = 4 -- Main/ClientMain compare this to spot an old copy; bump when this file changes
Net.ScriptFile = "03_Shared_Net" -- and this to spot another file's code pasted here

local EVENTS: { [string]: string } = {
	-- client → server
	ShootStart = "ShootStart", -- (shotNumber: number) echoed back in feedback
	ShootRelease = "ShootRelease", -- (holdTime: number)
	Finish = "Finish", -- (shotNumber: number, kind: "Layup" | "Dunk") the server judges it and may only downgrade a dunk
	LeaveQueue = "LeaveQueue", -- ()
	LeaveMatch = "LeaveMatch", -- () forfeit the current match
	Steal = "Steal", -- () reach for the ball carrier's ball
	Crossover = "Crossover", -- (direction: -1 | 1) switch hands with a sideways burst
	ClientReady = "ClientReady", -- (version: number) ClientMain checks in so Main can spot an old copy
	Buy = "Buy", -- (itemId: string) buy a cosmetic with coins
	Equip = "Equip", -- (slot: string, itemId: string) wear an owned cosmetic ("" takes it off)
	Emote = "Emote", -- (itemId: string) play an owned emote
	-- server → client
	Feedback = "Feedback", -- (kind: string, data: table)
}
Net.Events = EVENTS

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			local newFolder = Instance.new("Folder")
			newFolder.Name = FOLDER_NAME
			newFolder.Parent = ReplicatedStorage
			folder = newFolder
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Server: call once at startup before any client can use the remotes.
function Net.CreateAll()
	assert(RunService:IsServer(), "Net.CreateAll is server-only")
	local folder = getFolder()
	for _, name in Net.Events do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Net.Event(name: string): RemoteEvent
	assert(Net.Events[name] ~= nil, "Unknown remote: " .. name)
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		assert(remote and remote:IsA("RemoteEvent"), "Remote not created yet: " .. name)
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
