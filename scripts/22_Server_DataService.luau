--!strict
-- DataService (ModuleScript) — ServerScriptService > Server > DataService
-- Loads and saves each player's stats with DataStoreService. Nothing else
-- touches the DataStore. Each player's saved data is locked to the one server
-- they're on, so a quick rejoin elsewhere can't overwrite newer progress.
-- If saving isn't possible (Studio without API access, or a DataStore outage),
-- stats still work for the session and Output says why they aren't saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local DataService = {}
DataService.ScriptVersion = 1 -- Main compares this to spot an old copy; bump when this file changes
DataService.ScriptFile = "22_Server_DataService" -- and this to spot another file's code pasted here

local TAG = "[Street Hoops]"
local PROGRESSION = Config.Progression
local SCHEMA = 1

-- Every saved stat (a missing one starts at 0)
local STAT_NAMES = { "Wins", "Losses", "Draws", "Games", "Points", "Coins" }

-- "Loading": not loaded yet (changes are kept and added once it loads)
-- "Saved": loaded and being saved
-- "SessionOnly": counts for this session but isn't saved
export type Status = "Loading" | "Saved" | "SessionOnly"

type Profile = {
	Player: Player,
	Key: string,
	Stats: { [string]: any }, -- STAT_NAMES are numbers; fields a newer version added are kept as they are
	Pending: { [string]: number }, -- changes made while loading
	Status: Status,
	Session: string, -- this server's claim on the saved data
	Dirty: boolean,
	Saving: boolean,
	Released: boolean, -- the player left (or the server is closing): no more changes
}

-- Fires (player) whenever a player's stats or status change
DataService.Changed = Signal.new()

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local available = true -- false once we know this server can't use DataStores
local inFlight = 0 -- saves still running (shutdown waits for them)
local rng = Random.new()

--------------------------------------------------------------------------------
-- DataStore access, with retries
--------------------------------------------------------------------------------

local function unavailable(message: string)
	if not available then
		return
	end
	available = false
	warn(("%s ⚠ Player stats won't be saved on this server: %s"):format(TAG, message))
	warn(("%s   In Studio: publish the place (File > Publish to Roblox), then Home > Game Settings > Security and turn on 'Enable Studio Access to API Services'. Press Play again. Stats still count for this session."):format(TAG))
end

-- Errors that mean "DataStores can't be used here at all", not "try again"
local function isAccessError(message: string): boolean
	local lower = message:lower()
	return lower:find("studioaccess", 1, true) ~= nil
		or lower:find("studio access", 1, true) ~= nil
		or lower:find("publish", 1, true) ~= nil
		or lower:find("403", 1, true) ~= nil
end

local function getStore(): DataStore?
	if store or not available then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(PROGRESSION.StoreName)
	end)
	if ok then
		store = result
	else
		unavailable(tostring(result))
	end
	return store
end

local function waitForBudget()
	local deadline = os.clock() + 10
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 and os.clock() < deadline do
		task.wait(0.5)
	end
end

-- One UpdateAsync, retried with growing waits. True once it went through
-- (the transform itself may still have cancelled the write by returning nil).
local function update(key: string, transform: (any) -> any): boolean
	for attempt = 1, PROGRESSION.MaxAttempts do
		local dataStore = getStore()
		if not dataStore then
			return false
		end
		waitForBudget()
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(old)
				return transform(old)
			end)
		end)
		if ok then
			return true
		end
		local message = tostring(err)
		if isAccessError(message) then
			unavailable(message)
			return false
		end
		warn(("%s DataStore request for %s failed (try %d of %d): %s"):format(TAG, key, attempt, PROGRESSION.MaxAttempts, message))
		if attempt < PROGRESSION.MaxAttempts then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Saved record: { Schema, Stats = { ... }, Lock = { Session, Time } }
--------------------------------------------------------------------------------

local function readStats(record: any): { [string]: any }
	local saved = if typeof(record) == "table" and typeof(record.Stats) == "table" then record.Stats else {}
	local stats: { [string]: any } = table.clone(saved)
	for _, name in STAT_NAMES do
		local value = saved[name]
		stats[name] = if typeof(value) == "number" and value == value then math.max(0, math.floor(value)) else 0
	end
	return stats
end

local function lockOf(record: any): (string?, number)
	local lock = if typeof(record) == "table" then record.Lock else nil
	if typeof(lock) ~= "table" then
		return nil, 0
	end
	local session = if typeof(lock.Session) == "string" then lock.Session else nil
	local time = if typeof(lock.Time) == "number" then lock.Time else 0
	return session, time
end

-- A record to write: keeps any top-level fields a newer version added
local function makeRecord(old: any, stats: { [string]: any }, lock: { Session: string, Time: number }?): { [string]: any }
	local record: { [string]: any } = if typeof(old) == "table" then table.clone(old) else {}
	record.Schema = SCHEMA
	record.Stats = stats
	record.Lock = lock
	return record
end

-- A lock that hasn't been refreshed in this long belongs to a server that died
local function staleAfter(): number
	return PROGRESSION.AutosaveInterval * 3 + 60
end

--------------------------------------------------------------------------------
-- Load and save
--------------------------------------------------------------------------------

local function save(profile: Profile, release: boolean): boolean
	if profile.Status ~= "Saved" then
		return false
	end
	inFlight += 1
	while profile.Saving do
		task.wait(0.1)
	end
	if profile.Status ~= "Saved" then
		inFlight -= 1
		return false
	end
	profile.Saving = true
	profile.Dirty = false
	local snapshot = table.clone(profile.Stats)
	local lost = false
	local ok = update(profile.Key, function(old)
		local session = lockOf(old)
		if session ~= profile.Session then
			lost = true -- another server took over this player's data
			return nil
		end
		lost = false
		return makeRecord(old, snapshot, if release then nil else { Session = profile.Session, Time = os.time() })
	end)
	profile.Saving = false
	inFlight -= 1
	if ok and lost then
		profile.Status = "SessionOnly"
		warn(("%s ⚠ %s's stats are now saved by another server, so this one stopped saving them."):format(TAG, profile.Player.Name))
		DataService.Changed:Fire(profile.Player)
		return false
	end
	if not ok then
		profile.Dirty = true -- try again next time
		if available then
			warn(("%s ⚠ Couldn't save %s's stats; will try again."):format(TAG, profile.Player.Name))
		end
	end
	return ok
end

local function load(profile: Profile)
	local started = os.clock()
	local claimed: { [string]: any }? = nil
	while true do
		local lockedElsewhere = false
		-- After a while, take over anyway: the other server has had its chance
		local takeOver = os.clock() - started >= PROGRESSION.LockWaitTime
		local result: { [string]: any }? = nil
		local ok = update(profile.Key, function(old)
			local session, lockTime = lockOf(old)
			local heldElsewhere = session ~= nil and session ~= profile.Session and os.time() - lockTime < staleAfter()
			if heldElsewhere and not takeOver then
				lockedElsewhere = true
				return nil
			end
			lockedElsewhere = false
			local stats = readStats(old)
			result = stats
			return makeRecord(old, stats, { Session = profile.Session, Time = os.time() })
		end)
		if not ok then
			break -- DataStores unavailable, or every attempt failed
		end
		if not lockedElsewhere then
			claimed = result
			break
		end
		if not profile.Player.Parent then
			break -- left while we waited
		end
		task.wait(5)
	end

	if claimed then
		-- Add whatever happened while loading
		for name, amount in profile.Pending do
			claimed[name] = (claimed[name] or 0) + amount
		end
		profile.Dirty = next(profile.Pending) ~= nil
		profile.Stats = claimed
		profile.Status = "Saved"
	else
		profile.Status = "SessionOnly"
		if available and profile.Player.Parent then
			warn(("%s ⚠ Couldn't load %s's stats (DataStore problem). They count for this session but won't be saved."):format(TAG, profile.Player.Name))
		end
	end
	table.clear(profile.Pending)

	if profile.Released or not profile.Player.Parent then
		-- They left while loading: hand the data straight back
		profile.Released = true
		if claimed then
			save(profile, true)
		end
		if profiles[profile.Player] == profile then
			profiles[profile.Player] = nil
		end
		return
	end
	DataService.Changed:Fire(profile.Player)
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local stats: { [string]: any } = {}
	for _, name in STAT_NAMES do
		stats[name] = 0
	end
	local profile: Profile = {
		Player = player,
		Key = "Player_" .. player.UserId,
		Stats = stats,
		Pending = {},
		Status = "Loading",
		Session = ("%s/%d/%d"):format(game.JobId, os.time(), rng:NextInteger(1, 2 ^ 30)),
		Dirty = false,
		Saving = false,
		Released = false,
	}
	profiles[player] = profile
	DataService.Changed:Fire(player)
	task.spawn(load, profile)
end

local function onPlayerRemoving(player: Player)
	-- Deferred, so anything else reacting to the leave (a forfeit loss) is
	-- recorded before the final save
	task.defer(function()
		local profile = profiles[player]
		if not profile or profile.Released then
			return
		end
		profile.Released = true
		if profile.Status == "Loading" then
			return -- load() hands the data back when it finishes
		end
		save(profile, true)
		if profiles[player] == profile then
			profiles[player] = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function DataService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Autosave. Also refreshes each lock, so a crashed server's locks go stale.
	task.spawn(function()
		while true do
			task.wait(PROGRESSION.AutosaveInterval)
			for _, profile in profiles do
				if profile.Status == "Saved" and not profile.Released then
					task.spawn(save, profile, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		for _, profile in profiles do
			if profile.Status == "Saved" and not profile.Released then
				profile.Released = true
				task.spawn(save, profile, true)
			end
		end
		local deadline = os.clock() + PROGRESSION.ShutdownSaveTime
		task.wait() -- let the saves above start
		while inFlight > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Add to one of a player's stats (only the server's game rules call this)
function DataService.Increment(player: Player, stat: string, amount: number)
	local profile = profiles[player]
	if not profile or profile.Released or amount == 0 or not table.find(STAT_NAMES, stat) then
		return
	end
	profile.Stats[stat] = (profile.Stats[stat] or 0) + amount
	if profile.Status == "Loading" then
		profile.Pending[stat] = (profile.Pending[stat] or 0) + amount
	end
	profile.Dirty = true
	DataService.Changed:Fire(player)
end

-- A copy of a player's stats (nil if they aren't tracked)
function DataService.GetStats(player: Player): { [string]: number }?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local copy: { [string]: number } = {}
	for _, name in STAT_NAMES do
		copy[name] = profile.Stats[name] or 0
	end
	return copy
end

function DataService.GetStatus(player: Player): Status?
	local profile = profiles[player]
	return if profile then profile.Status else nil
end

DataService.StatNames = STAT_NAMES

return DataService
