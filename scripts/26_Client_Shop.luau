--!strict
-- Shop (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > Shop
-- The shop screen (SHOP button, B / gamepad Y, or the stand behind the spawn)
-- and the emote list (EMOTE button, G / gamepad D-pad up). It only shows what
-- the server published and sends requests; prices, coins and ownership are
-- all checked on the server.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent
local UIKit = require(Client:WaitForChild("UIKit"))
local MatchClient = require(Client:WaitForChild("MatchClient"))
local Hud = require(Client:WaitForChild("Hud"))

local Shop = {}
Shop.ScriptVersion = 1 -- ClientMain compares this to spot an old copy; bump when this file changes
Shop.ScriptFile = "26_Client_Shop" -- and this to spot another file's code pasted here

local THEME = Config.UI
local COSMETICS = Config.Cosmetics
local SHOP_ACTION = "StreetHoops_Shop"
local EMOTE_ACTION = "StreetHoops_EmoteMenu"
local player = Players.LocalPlayer

local TABS: { { Name: string, Slots: { [string]: boolean } } } = {
	{ Name = "BALLS", Slots = { Ball = true } },
	{ Name = "EFFECTS", Slots = { Effect = true } },
	{ Name = "EMOTES", Slots = { Emote = true } },
	{ Name = "GEAR", Slots = { Headband = true, Wristbands = true, Sleeve = true } },
}

local buyRemote: RemoteEvent
local equipRemote: RemoteEvent
local emoteRemote: RemoteEvent

local gui: ScreenGui
local shopButton: TextButton
local emoteButton: TextButton
local panel: Frame
local coinsLabel: TextLabel
local messageLabel: TextLabel
local loadingLabel: TextLabel
local grid: ScrollingFrame
local tabButtons: { TextButton } = {}
local emoteList: Frame
local currentTab = 1
local cards: { [string]: { Frame: Frame, Status: TextLabel, Button: TextButton } } = {}

--------------------------------------------------------------------------------
-- What we own and wear (published by the server on our Player)
--------------------------------------------------------------------------------

local function ownedSet(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	local text = player:GetAttribute("CosmeticsOwned")
	if typeof(text) == "string" then
		for _, id in string.split(text, ",") do
			if id ~= "" then
				set[id] = true
			end
		end
	end
	return set
end

local function owns(item: Config.CosmeticItem, owned: { [string]: boolean }): boolean
	return item.Price <= 0 or owned[item.Id] == true
end

local function equippedIn(slot: string): string
	local id = player:GetAttribute("Equipped" .. slot)
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return if slot == "Ball" then COSMETICS.DefaultBall else ""
end

local function coins(): number
	local value = player:GetAttribute("Coins")
	return if typeof(value) == "number" then value else 0
end

local function ready(): boolean
	return player:GetAttribute("CosmeticsReady") == true
end

-- In a match that's under way: the shop and emotes wait (results screen is fine)
local function busyPlaying(): boolean
	local court, role = MatchClient.GetMyCourt()
	if role ~= "Playing" or not court then
		return false
	end
	local state = court:GetAttribute("State")
	return state ~= "GameOver" and state ~= "Idle"
end

local function emoteAllowed(): boolean
	return not busyPlaying() and MatchClient.GetHeldBall() == nil
end

--------------------------------------------------------------------------------
-- Building the screen
--------------------------------------------------------------------------------

-- Phones: top right, clear of the thumbstick (which takes touches on the lower
-- left). Elsewhere: middle of the left edge.
local function sideButton(name: string, text: string, color: Color3, order: number): TextButton
	local touch = UserInputService.TouchEnabled
	local button = UIKit.new("TextButton", {
		Name = name,
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0, 0.5),
		Position = if touch then UDim2.new(1, -16, 0, 8 + (order - 1) * 50) else UDim2.new(0, 16, 0.42, (order - 1) * 54),
		Size = UDim2.fromOffset(104, 44),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		Text = text,
		TextColor3 = THEME.Text,
		Font = THEME.FontHeavy,
		TextScaled = true,
		AutoButtonColor = true,
		Parent = gui,
	}, { UIKit.corner(10) :: Instance, UIKit.padding(8) })
	UIKit.stroke(Color3.new(1, 1, 1), 2, 0.6).Parent = button
	return button
end

local function smallButton(parent: Instance, text: string, color: Color3): TextButton
	local button = UIKit.new("TextButton", {
		Size = UDim2.new(1, -16, 0, 30),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		BackgroundColor3 = color,
		Text = text,
		TextColor3 = THEME.Text,
		Font = THEME.FontHeavy,
		TextScaled = true,
		AutoButtonColor = true,
		Parent = parent,
	}, { UIKit.corner(8) :: Instance, UIKit.padding(5) })
	return button
end

-- A little picture of the item: a coloured ball, burst, band or emote label
local function swatch(item: Config.CosmeticItem, parent: Instance)
	local holder = UIKit.new("Frame", {
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		BackgroundColor3 = THEME.PanelLight,
		Parent = parent,
	}, { UIKit.corner(32) })
	if item.Slot == "Emote" then
		UIKit.text({ Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.25), Text = "EMOTE", TextColor3 = THEME.TextDim, Parent = holder })
		return
	end
	local main = item.Color or THEME.Text
	local inner = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if item.Slot == "Ball" then UDim2.fromScale(0.8, 0.8) else UDim2.fromScale(0.8, 0.3),
		BackgroundColor3 = main,
		Parent = holder,
	}, { UIKit.corner(if item.Slot == "Ball" then 26 else 6) })
	if item.Accent then
		UIKit.stroke(item.Accent, 3, 0).Parent = inner
	end
end

local function buildCard(item: Config.CosmeticItem)
	local card = UIKit.panel({
		Name = item.Id,
		BackgroundColor3 = THEME.PanelLight,
		Parent = grid,
	})
	swatch(item, card)
	UIKit.text({
		Name = "ItemName",
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(6, 80),
		Text = item.Name,
		Font = THEME.FontHeavy,
		Parent = card,
	})
	local status = UIKit.text({
		Name = "Status",
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(6, 102),
		TextColor3 = THEME.TextDim,
		Font = THEME.FontBody,
		Parent = card,
	})
	local button = smallButton(card, "", THEME.Accent)
	button.Name = "Action"
	button.Activated:Connect(function()
		Shop.Act(item.Id)
	end)
	cards[item.Id] = { Frame = card, Status = status, Button = button }
end

local function build()
	gui = UIKit.new("ScreenGui", {
		Name = "StreetHoopsShop",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 8,
		Parent = player:WaitForChild("PlayerGui"),
	})
	shopButton = sideButton("ShopButton", "SHOP", THEME.Accent, 1)
	emoteButton = sideButton("EmoteButton", "EMOTE", THEME.PanelLight, 2)

	panel = UIKit.panel({
		Name = "ShopPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 470),
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	})
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(700, 470), Parent = panel })
	UIKit.text({
		Name = "Title",
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.fromOffset(200, 34),
		Text = "SHOP",
		Font = THEME.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	coinsLabel = UIKit.text({
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -64, 0, 16),
		Size = UDim2.fromOffset(220, 26),
		TextColor3 = THEME.Good,
		Font = THEME.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})
	local close = UIKit.new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = THEME.PanelLight,
		Text = "X",
		TextColor3 = THEME.Text,
		Font = THEME.FontHeavy,
		TextScaled = true,
		Modal = true, -- frees the mouse (shift lock, first person) while the shop is open
		Parent = panel,
	}, { UIKit.corner(8) :: Instance, UIKit.padding(8) })
	close.Activated:Connect(function()
		Shop.SetOpen(false)
	end)

	for i, tab in TABS do
		local button = UIKit.new("TextButton", {
			Name = "Tab" .. tab.Name,
			Position = UDim2.new((i - 1) / #TABS, 18 - (i - 1) * 36 / #TABS, 0, 58),
			Size = UDim2.new(1 / #TABS, -36 / #TABS - 6, 0, 34),
			BackgroundColor3 = THEME.PanelLight,
			Text = tab.Name,
			TextColor3 = THEME.Text,
			Font = THEME.FontHeavy,
			TextScaled = true,
			Parent = panel,
		}, { UIKit.corner(8) :: Instance, UIKit.padding(7) })
		button.Activated:Connect(function()
			currentTab = i
			Shop.Refresh()
		end)
		tabButtons[i] = button
	end

	grid = UIKit.new("ScrollingFrame", {
		Name = "Items",
		Position = UDim2.fromOffset(18, 102),
		Size = UDim2.new(1, -36, 1, -150),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 168),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i, item in COSMETICS.Items do
		buildCard(item)
		cards[item.Id].Frame.LayoutOrder = i
	end

	messageLabel = UIKit.text({
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -36, 0, 24),
		TextColor3 = THEME.TextDim,
		Font = THEME.FontBody,
		Text = "Earn coins by playing matches. Everyone sees what you wear.",
		Parent = panel,
	})
	loadingLabel = UIKit.text({
		Name = "Loading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0.8, 0, 0, 30),
		Text = "Loading your items…",
		Visible = false,
		Parent = panel,
	})

	local touch = UserInputService.TouchEnabled
	emoteList = UIKit.panel({
		Name = "EmoteList",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0, 0.5),
		Position = if touch then UDim2.new(1, -132, 0, 8) else UDim2.new(0, 132, 0.42, 54),
		Size = UDim2.fromOffset(210, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	})
	UIKit.padding(8).Parent = emoteList
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = emoteList })

	-- Shrink both to fit small screens (phones)
	local panelScale = UIKit.new("UIScale", { Parent = panel })
	local emoteScale = UIKit.new("UIScale", { Parent = emoteList })
	local function fitToScreen()
		local area = gui.AbsoluteSize
		if area.X <= 0 or area.Y <= 0 then
			return
		end
		panelScale.Scale = math.min(1, (area.Y - 24) / 470, (area.X - 24) / 700)
		emoteScale.Scale = math.min(1, (area.Y - 24) / 260)
	end
	fitToScreen()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)
end

--------------------------------------------------------------------------------
-- Keeping it up to date
--------------------------------------------------------------------------------

local function setButton(button: TextButton, text: string, color: Color3, enabled: boolean)
	button.Text = text
	button.BackgroundColor3 = color
	button.AutoButtonColor = enabled
	button.BackgroundTransparency = if enabled then 0 else 0.45
end

function Shop.Refresh()
	if not panel then
		return
	end
	local owned = ownedSet()
	local money = coins()
	coinsLabel.Text = ("%d coins"):format(money)
	local isReady = ready()
	loadingLabel.Visible = not isReady
	grid.Visible = isReady
	for i, button in tabButtons do
		button.BackgroundColor3 = if i == currentTab then THEME.Accent else THEME.PanelLight
	end
	local slots = TABS[currentTab].Slots
	for _, item in COSMETICS.Items do
		local card = cards[item.Id]
		card.Frame.Visible = slots[item.Slot] == true
		local has = owns(item, owned)
		if not has then
			card.Status.Text = ("%d coins"):format(item.Price)
			if money >= item.Price then
				setButton(card.Button, "BUY", THEME.Good, true)
			else
				setButton(card.Button, "BUY", THEME.PanelLight, false)
			end
		elseif item.Slot == "Emote" then
			card.Status.Text = "Owned"
			setButton(card.Button, "PLAY", THEME.Home, true)
		elseif equippedIn(item.Slot) == item.Id then
			card.Status.Text = "Wearing"
			if item.Slot == "Ball" then
				setButton(card.Button, "EQUIPPED", THEME.Perfect, false)
			else
				setButton(card.Button, "TAKE OFF", THEME.Bad, true)
			end
		else
			card.Status.Text = "Owned"
			setButton(card.Button, "EQUIP", THEME.Home, true)
		end
	end
end

local function refreshEmotes()
	for _, child in emoteList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local owned = ownedSet()
	local n = 0
	for _, item in COSMETICS.Items do
		if item.Slot == "Emote" and owns(item, owned) then
			n += 1
			local key = n
			local button = UIKit.new("TextButton", {
				Name = item.Id,
				LayoutOrder = n,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = THEME.PanelLight,
				Text = ("%d   %s"):format(key, item.Name),
				TextColor3 = THEME.Text,
				Font = THEME.Font,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Modal = true, -- frees the mouse while the list is open
				Parent = emoteList,
			}, { UIKit.corner(8) :: Instance, UIKit.padding(7) })
			button.Activated:Connect(function()
				Shop.PlayEmote(item.Id)
			end)
		end
	end
end

local function usingGamepad(): boolean
	return string.find(UserInputService:GetLastInputType().Name, "Gamepad", 1, true) ~= nil
end

local function hideEmotes()
	emoteList.Visible = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(emoteList) then
		GuiService.SelectedObject = nil
	end
end

-- A controller has no number keys: put its selection on the first emote
local function selectFirstEmote()
	if not emoteList.Visible or not usingGamepad() then
		return
	end
	for _, child in emoteList:GetChildren() do
		if child:IsA("TextButton") and child.LayoutOrder == 1 then
			GuiService.SelectedObject = child
			return
		end
	end
end

local function refreshButtons()
	local playing = busyPlaying()
	shopButton.Visible = not playing
	emoteButton.Visible = emoteAllowed()
	if playing and panel.Visible then
		Shop.SetOpen(false)
	end
	if not emoteButton.Visible and emoteList.Visible then
		hideEmotes()
	end
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

function Shop.SetOpen(open: boolean)
	if open and busyPlaying() then
		Hud.Toast("The shop opens again after your match", THEME.TextDim, 1.8)
		return
	end
	panel.Visible = open
	if open then
		hideEmotes()
		Shop.Refresh()
		if usingGamepad() then
			GuiService.SelectedObject = tabButtons[currentTab]
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then
		GuiService.SelectedObject = nil
	end
end

function Shop.IsOpen(): boolean
	return panel.Visible
end

function Shop.PlayEmote(id: string)
	hideEmotes()
	if not emoteAllowed() then
		Hud.Toast("Emotes wait until you don't have the ball and play stops", THEME.TextDim, 1.8)
		return
	end
	emoteRemote:FireServer(id)
end

-- The button on an item card: buy it, wear it, take it off, or play it
function Shop.Act(id: string)
	local item: Config.CosmeticItem? = nil
	for _, candidate in COSMETICS.Items do
		if candidate.Id == id then
			item = candidate
		end
	end
	if not item or not ready() then
		return
	end
	local owned = ownedSet()
	if not owns(item, owned) then
		if coins() >= item.Price then
			buyRemote:FireServer(id)
		end
	elseif item.Slot == "Emote" then
		Shop.SetOpen(false)
		Shop.PlayEmote(id)
	elseif equippedIn(item.Slot) == id then
		if item.Slot ~= "Ball" then
			equipRemote:FireServer(item.Slot, "")
		end
	else
		equipRemote:FireServer(item.Slot, id)
	end
end

local function toggleEmotes()
	if emoteList.Visible then
		hideEmotes()
		return
	end
	if not emoteAllowed() then
		Hud.Toast("Emotes wait until you don't have the ball and play stops", THEME.TextDim, 1.8)
		return
	end
	Shop.SetOpen(false)
	refreshEmotes()
	emoteList.Visible = true
	selectFirstEmote()
end

function Shop.Init()
	buyRemote = Net.Event("Buy")
	equipRemote = Net.Event("Equip")
	emoteRemote = Net.Event("Emote")
	build()

	shopButton.Activated:Connect(function()
		Shop.SetOpen(not panel.Visible)
	end)
	emoteButton.Activated:Connect(toggleEmotes)

	-- B / gamepad Y: shop. G / D-pad up: emotes. 1-6 play one while the list is open.
	ContextActionService:BindAction(SHOP_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			Shop.SetOpen(not panel.Visible)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction(EMOTE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			toggleEmotes()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G, Enum.KeyCode.DPadUp)
	local numberKeys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not emoteList.Visible then
			return
		end
		local index = table.find(numberKeys, input.KeyCode)
		local choice: TextButton? = nil
		if index then
			for _, child in emoteList:GetChildren() do
				if child:IsA("TextButton") and child.LayoutOrder == index then
					choice = child
				end
			end
		end
		if choice then
			Shop.PlayEmote((choice :: TextButton).Name)
		end
	end)

	-- The stand behind the spawn opens the shop too
	task.spawn(function()
		local park = workspace:WaitForChild("Park", 60)
		local stand = park and park:WaitForChild("ShopStand", 30)
		local counter = stand and stand:WaitForChild("Counter", 10)
		local prompt = counter and counter:WaitForChild("ShopPrompt", 10)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(who)
				if who == player then
					Shop.SetOpen(true)
				end
			end)
		end
	end)

	-- Replies to buying (the server decides)
	Net.Event("Feedback").OnClientEvent:Connect(function(kind: string, data: any)
		if kind ~= "Shop" or typeof(data) ~= "table" or typeof(data.Text) ~= "string" then
			return
		end
		messageLabel.Text = data.Text
		messageLabel.TextColor3 = if data.Ok == true then THEME.Perfect else THEME.Bad
		Hud.Toast(data.Text, if data.Ok == true then THEME.Perfect else THEME.Bad, 2)
	end)

	for _, name in { "Coins", "CosmeticsOwned", "CosmeticsReady", "EquippedBall", "EquippedEffect", "EquippedHeadband", "EquippedWristbands", "EquippedSleeve" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			Shop.Refresh()
			if emoteList.Visible then
				-- Rebuilding the rows drops a controller's selection: put it back
				local selected = GuiService.SelectedObject
				local hadSelection = selected ~= nil and selected:IsDescendantOf(emoteList)
				refreshEmotes()
				if hadSelection then
					selectFirstEmote()
				end
			end
		end)
	end
	MatchClient.Changed:Connect(refreshButtons)
	refreshButtons()
	Shop.Refresh()
end

return Shop
