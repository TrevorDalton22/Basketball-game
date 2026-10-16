--!strict
-- RemoteGuard (ModuleScript) — ServerScriptService > Server > RemoteGuard
-- Per-player token bucket shared by every client → server remote handler.
-- Spammed or malformed requests are dropped before any game logic runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local RemoteGuard = {}
RemoteGuard.ScriptFile = "07_Server_RemoteGuard" -- Main/ClientMain compare this to spot another file's code pasted here

type Bucket = { Tokens: number, Updated: number }
local buckets: { [Player]: Bucket } = {}

function RemoteGuard.Allow(player: Player): boolean
	local rate = Config.Remote.MaxEventsPerSecond
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { Tokens = rate, Updated = now }
		buckets[player] = bucket
	end
	bucket.Tokens = math.min(rate, bucket.Tokens + (now - bucket.Updated) * rate)
	bucket.Updated = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

-- A finite number inside [min, max]
function RemoteGuard.IsNumber(value: any, min: number, max: number): boolean
	return typeof(value) == "number" and value == value and value >= min and value <= max
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RemoteGuard
