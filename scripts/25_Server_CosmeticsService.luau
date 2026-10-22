--!strict
-- CosmeticsService (ModuleScript) — ServerScriptService > Server > CosmeticsService
-- The shop. Buying (the price is checked and the coins spent here, on the
-- server), wearing items, playing emotes, and the gear parts on characters.
-- What everyone owns and wears is published as player attributes; each client
-- shows ball skins, score effects and emotes itself from those.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Server = script.Parent
local DataService = require(Server:WaitForChild("DataService"))
local MatchService = require(Server:WaitForChild("MatchService"))
local BallService = require(Server:WaitForChild("BallService"))
local RemoteGuard = require(Server:WaitForChild("RemoteGuard"))

local CosmeticsService = {}
CosmeticsService.ScriptVersion = 1 -- Main compares this to spot an old copy; bump when this file changes
CosmeticsService.ScriptFile = "25_Server_CosmeticsService" -- and this to spot another file's code pasted here

local COSMETICS = Config.Cosmetics
local EMOTE_ATTRIBUTE = "StreetHoopsEmote" -- "Flex:12": a new value every time someone emotes
local GEAR_FOLDER = "StreetHoopsGear"
local GEAR_SLOTS = { "Headband", "Wristbands", "Sleeve" }

local items: { [string]: Config.CosmeticItem } = {}
for _, item in COSMETICS.Items do
	items[item.Id] = item
end
local wearable: { [string]: boolean } = {}
for _, slot in COSMETICS.Slots do
	wearable[slot] = true
end

local feedback: RemoteEvent
local lastEmote: { [Player]: number } = {}
local emoteSerial = 0
local builtGear: { [Player]: string } = {} -- the gear on their current character, e.g. "HeadbandRed||"
local buildGear: (Player) -> ()

local function owns(inventory: DataService.Inventory, item: Config.CosmeticItem): boolean
	return item.Price <= 0 or inventory.Owned[item.Id] == true
end

local function reply(player: Player, ok: boolean, text: string)
	feedback:FireClient(player, "Shop", { Ok = ok, Text = text })
end

--------------------------------------------------------------------------------
-- What each player owns and wears, for every client to see
--------------------------------------------------------------------------------

-- Attributes: CosmeticsReady (their items have loaded), CosmeticsOwned (bought
-- item Ids, comma-separated; free ones are always owned), Equipped<Slot> (an
-- item Id, or "" for nothing / the default ball)
local function publish(player: Player)
	if not player.Parent then
		return
	end
	local inventory = DataService.GetInventory(player)
	player:SetAttribute("CosmeticsReady", inventory ~= nil)
	if not inventory then
		return
	end
	local owned = {}
	for id in inventory.Owned do
		if items[id] then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	player:SetAttribute("CosmeticsOwned", table.concat(owned, ","))
	for _, slot in COSMETICS.Slots do
		local id = inventory.Equipped[slot]
		local item = if id then items[id] else nil
		-- Only something they own that is still in the shop
		local shown = if item and item.Slot == slot and owns(inventory, item) then item.Id else ""
		player:SetAttribute("Equipped" .. slot, shown)
	end
	-- Rebuild the gear only when it changed
	local wearing = {}
	for _, slot in GEAR_SLOTS do
		local id = player:GetAttribute("Equipped" .. slot)
		table.insert(wearing, if typeof(id) == "string" then id else "")
	end
	if table.concat(wearing, "|") ~= builtGear[player] then
		buildGear(player)
	end
end

--------------------------------------------------------------------------------
-- Gear: real parts welded to the character, so everyone sees them
--------------------------------------------------------------------------------

local function gearPart(name: string, item: Config.CosmeticItem, shape: Enum.PartType, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = item.Color or Color3.new(1, 1, 1)
	part.Material = item.Material or Enum.Material.Fabric
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Weld `part` to a body part at `offset` (in the body part's space)
local function wear(folder: Folder, body: BasePart, part: Part, offset: CFrame)
	part.CFrame = body.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = folder
end

local function bodyPart(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- A cylinder runs along its X axis; this stands it up along the body part's Y
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

function buildGear(player: Player)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local old = character:FindFirstChild(GEAR_FOLDER)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = GEAR_FOLDER
	local function equipped(slot: string): Config.CosmeticItem?
		local id = player:GetAttribute("Equipped" .. slot)
		return if typeof(id) == "string" then items[id] else nil
	end

	local headband = equipped("Headband")
	local head = bodyPart(character, "Head")
	if headband and head then
		-- The head as drawn: a classic head (R6, older R15) is a mesh bigger than its part
		local size = head.Size
		local width, height = math.min(size.X, size.Z), size.Y
		local mesh = head:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshType == Enum.MeshType.Head then
			width *= mesh.Scale.X
			height *= mesh.Scale.Y
		elseif mesh then
			width, height = math.max(width, 1.25), math.max(height, 1.25)
		end
		local diameter = width * 1.04 + 0.04
		wear(folder, head, gearPart("Headband", headband, Enum.PartType.Cylinder, Vector3.new(height * 0.22, diameter, diameter)), CFrame.new(0, height * 0.2, 0) * UPRIGHT)
	end

	local wristbands = equipped("Wristbands")
	if wristbands then
		for _, side in { "Right", "Left" } do
			-- R15 forearm, or the whole R6 arm (its lower end is the hand)
			local forearm = bodyPart(character, side .. "LowerArm")
			local arm = forearm or bodyPart(character, side .. " Arm")
			if arm then
				local size = arm.Size
				-- Wide enough to cover the corners of a blocky arm
				local diameter = math.sqrt(size.X * size.X + size.Z * size.Z) * 1.03
				local fromBottom = if forearm then 0.2 else 0.45
				wear(folder, arm, gearPart("Wristband", wristbands, Enum.PartType.Cylinder, Vector3.new(0.3, diameter, diameter)), CFrame.new(0, -size.Y / 2 + fromBottom, 0) * UPRIGHT)
			end
		end
	end

	local sleeve = equipped("Sleeve")
	if sleeve then
		-- On the shooting arm: upper arm and most of the forearm (R15), or the upper R6 arm
		local upper = bodyPart(character, "RightUpperArm")
		local lower = bodyPart(character, "RightLowerArm")
		if upper then
			wear(folder, upper, gearPart("Sleeve", sleeve, Enum.PartType.Block, upper.Size * Vector3.new(1.08, 0.94, 1.08)), CFrame.identity)
			if lower then
				local size = lower.Size
				wear(folder, lower, gearPart("Sleeve", sleeve, Enum.PartType.Block, Vector3.new(size.X * 1.08, size.Y * 0.6, size.Z * 1.08)), CFrame.new(0, size.Y * 0.18, 0))
			end
		else
			local arm = bodyPart(character, "Right Arm")
			if arm then
				local size = arm.Size
				wear(folder, arm, gearPart("Sleeve", sleeve, Enum.PartType.Block, Vector3.new(size.X * 1.08, size.Y * 0.6, size.Z * 1.08)), CFrame.new(0, size.Y * 0.18, 0))
			end
		end
	end

	if #folder:GetChildren() > 0 then
		folder.Parent = character
	else
		folder:Destroy()
	end
	local wearing = {}
	for _, slot in GEAR_SLOTS do
		local id = player:GetAttribute("Equipped" .. slot)
		table.insert(wearing, if typeof(id) == "string" then id else "")
	end
	builtGear[player] = table.concat(wearing, "|")
end

--------------------------------------------------------------------------------
-- Requests from the shop
--------------------------------------------------------------------------------

local function onBuy(player: Player, id: any)
	if not RemoteGuard.Allow(player) or typeof(id) ~= "string" then
		return
	end
	local item = items[id]
	if not item or item.Price <= 0 then
		return
	end
	local ok, why = DataService.Buy(player, id, item.Price)
	if ok then
		-- Wear it straight away (an emote just joins your list)
		if item.Slot ~= "Emote" then
			DataService.Equip(player, item.Slot, id)
		end
		reply(player, true, ("Bought %s!"):format(item.Name))
	elseif why == "Coins" then
		reply(player, false, ("Not enough coins for %s (%d)"):format(item.Name, item.Price))
	elseif why == "Owned" then
		reply(player, false, ("You already own %s"):format(item.Name))
	elseif why == "Loading" then
		reply(player, false, "Your items are still loading. Try again in a moment.")
	end
end

local function onEquip(player: Player, slot: any, id: any)
	if not RemoteGuard.Allow(player) or typeof(slot) ~= "string" or not wearable[slot] then
		return
	end
	if id == "" then
		DataService.Equip(player, slot, nil)
		return
	end
	if typeof(id) ~= "string" then
		return
	end
	local item = items[id]
	local inventory = DataService.GetInventory(player)
	if item and item.Slot == slot and inventory and owns(inventory, item) then
		DataService.Equip(player, slot, id)
	end
end

local function onEmote(player: Player, id: any)
	if not RemoteGuard.Allow(player) or typeof(id) ~= "string" then
		return
	end
	local item = items[id]
	if not item or item.Slot ~= "Emote" or not item.Emote then
		return
	end
	-- Free emotes work even before their items have loaded
	local inventory = DataService.GetInventory(player)
	if item.Price > 0 and not (inventory and owns(inventory, item)) then
		return
	end
	local now = os.clock()
	local last = lastEmote[player]
	if last and now - last < COSMETICS.EmoteCooldown then
		return
	end
	if BallService.FindHeldBy(player) then
		reply(player, false, "Pass on the emote while you have the ball")
		return
	end
	-- Not during a match (the results screen is fine), like the shop screen
	for _, cs in MatchService.GetCourtStates() do
		if (cs.Home == player or cs.Away == player) and cs.State ~= "GameOver" then
			reply(player, false, "Emotes wait for a break in play")
			return
		end
	end
	lastEmote[player] = now
	emoteSerial += 1
	player:SetAttribute(EMOTE_ATTRIBUTE, ("%s:%d"):format(item.Emote :: string, emoteSerial))
end

--------------------------------------------------------------------------------

function CosmeticsService.Init()
	feedback = Net.Event("Feedback")
	Net.Event("Buy").OnServerEvent:Connect(onBuy)
	Net.Event("Equip").OnServerEvent:Connect(onEquip)
	Net.Event("Emote").OnServerEvent:Connect(onEmote)
	DataService.Changed:Connect(publish)

	local function onPlayerAdded(player: Player)
		publish(player)
		player.CharacterAdded:Connect(function()
			task.defer(buildGear, player)
		end)
		-- The avatar's own look can arrive a moment after the character
		player.CharacterAppearanceLoaded:Connect(function()
			buildGear(player)
		end)
		if player.Character then
			task.defer(buildGear, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastEmote[player] = nil
		builtGear[player] = nil
	end)

	-- Studio only, for trying the shop: give everyone in the test coins from the
	-- Command Bar (server view):
	--   game.ServerScriptService.Server.CosmeticsService.GiveCoins:Invoke(3000)
	-- Clients can't reach a BindableFunction on the server, and live servers don't get one.
	if RunService:IsStudio() then
		local give = Instance.new("BindableFunction")
		give.Name = "GiveCoins"
		give.OnInvoke = function(amount: any): string
			if typeof(amount) ~= "number" or not (amount >= 1 and amount <= 1e6) then
				return "Pass a number of coins from 1 to 1000000, for example GiveCoins:Invoke(3000)"
			end
			local given = {}
			for _, player in Players:GetPlayers() do
				DataService.Increment(player, "Coins", math.floor(amount))
				table.insert(given, player.Name)
			end
			return ("Gave %d coins to %s"):format(math.floor(amount), if #given > 0 then table.concat(given, ", ") else "nobody (no players yet)")
		end
		give.Parent = script
	end
end

return CosmeticsService
