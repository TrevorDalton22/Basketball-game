--!strict
-- Hud (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > Hud
-- All 2D interface: scoreboard + shot clock, banners, toasts, queue panel,
-- results screen, leave-match button and the context hint. It only displays
-- what the server published (court attributes + Feedback events) and sends
-- LeaveQueue / LeaveMatch requests.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent
local UIKit = require(Client:WaitForChild("UIKit"))
local MatchClient = require(Client:WaitForChild("MatchClient"))

local Hud = {}

local THEME = Config.UI
local player = Players.LocalPlayer
local LEAVE_QUEUE_ACTION = "StreetHoops_LeaveQueue"
local LEAVE_MATCH_ACTION = "StreetHoops_LeaveMatch"
local maxToasts = 3 -- lowered on short phone screens so toasts never cover the hint

local leaveQueue: RemoteEvent
local leaveMatch: RemoteEvent

-- One UIScale per top-level element so each scales around its own anchor point
local scales: { UIScale } = {}
local scoreboard: Frame
local homeName: TextLabel
local awayName: TextLabel
local homeScore: TextLabel
local awayScore: TextLabel
local homeBall: Frame
local awayBall: Frame
local clockLabel: TextLabel
local subLabel: TextLabel
local shotClock: Frame
local shotClockLabel: TextLabel
local leaveMatchButton: TextButton
local banner: TextLabel
local bannerSub: TextLabel
local toastHolder: Frame
local queuePanel: Frame
local queueTitle: TextLabel
local queueStatus: TextLabel
local queueKeys: TextLabel
local leaveButton: TextButton
local results: Frame
local resultsTitle: TextLabel
local resultsScore: TextLabel
local resultsReason: TextLabel
local hint: TextLabel

local lastState: string? = nil
local lastBannerMessage = ""
local lastCountdown = -1
local bannerToken = 0
local leaveQueueBound = false
local leaveMatchBound = false
local confirmToken = 0
local confirmPending = false
local toastCount = 0

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

type InputKind = "Touch" | "Gamepad" | "Keyboard"

local function inputKind(): InputKind
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:find("Gamepad") then
		return "Gamepad"
	end
	return "Keyboard"
end

local function shootPrompt(): string
	local kind = inputKind()
	if kind == "Touch" then
		return "Hold SHOOT"
	elseif kind == "Gamepad" then
		return "Hold R2"
	end
	return "Hold E"
end

local function crossoverPrompt(): string
	local kind = inputKind()
	if kind == "Touch" then
		return "MOVE to cross over"
	elseif kind == "Gamepad" then
		return "L1 to cross over"
	end
	return "Q to cross over"
end

local function defensePrompt(): string
	local kind = inputKind()
	if kind == "Touch" then
		return "STEAL when close · jump in front of a shot to block"
	elseif kind == "Gamepad" then
		return "R2 to steal when close · A (jump) in front of a shot to block"
	end
	return "E to steal when close · Space (jump) in front of a shot to block"
end

local function attrNumber(court: Model, name: string): number
	local value = court:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function attrString(court: Model, name: string): string
	local value = court:GetAttribute(name)
	return if typeof(value) == "string" then value else ""
end

-- Wrapped, scaled text that never shrinks below a readable size
local function readable(label: TextLabel, minSize: number, maxSize: number)
	label.TextWrapped = true
	UIKit.new("UITextSizeConstraint", { MinTextSize = minSize, MaxTextSize = maxSize, Parent = label })
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function teamBlock(side: string, color: Color3): (Frame, TextLabel, TextLabel, Frame)
	local isHome = side == "Home"
	local block = UIKit.new("Frame", {
		Name = side,
		Size = UDim2.new(0.38, 0, 1, 0),
		Position = if isHome then UDim2.fromScale(0, 0) else UDim2.fromScale(0.62, 0),
		BackgroundTransparency = 1,
	})
	UIKit.new("Frame", {
		Name = "Stripe",
		Size = UDim2.new(0, 6, 1, -16),
		Position = if isHome then UDim2.fromOffset(8, 8) else UDim2.new(1, -14, 0, 8),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = block,
	}, { UIKit.corner(3) })
	local name = UIKit.text({
		Name = "PlayerName",
		Size = UDim2.new(1, -96, 0, 22),
		Position = if isHome then UDim2.fromOffset(22, 10) else UDim2.fromOffset(74, 10),
		TextXAlignment = if isHome then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		TextColor3 = THEME.TextDim,
		Font = THEME.Font,
		Parent = block,
	})
	local score = UIKit.text({
		Name = "Score",
		Size = UDim2.new(0, 62, 1, -12),
		Position = if isHome then UDim2.new(1, -66, 0, 6) else UDim2.fromOffset(4, 6),
		Font = THEME.FontHeavy,
		Text = "0",
		Parent = block,
	})
	local ball = UIKit.new("Frame", {
		Name = "Possession",
		Size = UDim2.fromOffset(14, 14),
		Position = if isHome then UDim2.fromOffset(22, 42) else UDim2.new(1, -36, 0, 42),
		BackgroundColor3 = Config.Ball.Color,
		Visible = false,
		Parent = block,
	}, { UIKit.corner(7) })
	return block, name, score, ball
end

local function build()
	local gui = UIKit.new("ScreenGui", {
		Name = "StreetHoopsHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local root = UIKit.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})

	-- Scoreboard (below the Roblox top bar) ----------------------------------
	scoreboard = UIKit.panel({
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(560, 68),
		Visible = false,
		Parent = root,
	})
	UIKit.gradient(THEME.PanelLight, THEME.Panel).Parent = scoreboard
	local homeBlock, awayBlock
	homeBlock, homeName, homeScore, homeBall = teamBlock("Home", THEME.Home)
	awayBlock, awayName, awayScore, awayBall = teamBlock("Away", THEME.Away)
	homeBlock.Parent = scoreboard
	awayBlock.Parent = scoreboard
	clockLabel = UIKit.text({
		Name = "Clock",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0.24, 0, 0, 34),
		Font = THEME.FontHeavy,
		Text = "4:00",
		Parent = scoreboard,
	})
	subLabel = UIKit.text({
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 42),
		Size = UDim2.new(0.24, 0, 0, 16),
		TextColor3 = THEME.Accent,
		Text = "FIRST TO 15",
		Parent = scoreboard,
	})

	-- Shot clock pill hanging under the scoreboard
	shotClock = UIKit.panel({
		Name = "ShotClock",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(96, 28),
		Visible = false,
		Parent = scoreboard,
	})
	shotClockLabel = UIKit.text({
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Font = THEME.FontHeavy,
		Parent = shotClock,
	})

	-- Leave match (two taps to confirm)
	leaveMatchButton = UIKit.new("TextButton", {
		Name = "LeaveMatch",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 1, 6),
		Size = UDim2.fromOffset(170, 28),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = 0.15,
		Text = "LEAVE MATCH",
		TextColor3 = THEME.TextDim,
		Font = THEME.Font,
		TextScaled = true,
		-- Not gamepad-selectable: a controller forfeits with D-pad down (twice)
		Selectable = false,
		Parent = scoreboard,
	}, { UIKit.corner(8) :: Instance, UIKit.padding(5) })
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 14, Parent = leaveMatchButton })

	-- Banner (countdown, scores, turnovers) ----------------------------------
	banner = UIKit.text({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(700, 110),
		Font = THEME.FontHeavy,
		TextStrokeTransparency = 0.5,
		Visible = false,
		Parent = root,
	})
	bannerSub = UIKit.text({
		Name = "BannerSub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0.8, 0, 0, 34),
		Font = THEME.Font,
		TextColor3 = THEME.TextDim,
		TextStrokeTransparency = 0.6,
		Parent = banner,
	})

	-- Toasts: below the banner so they never cover it ------------------------
	toastHolder = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(420, 140),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toastHolder,
	})

	-- Queue panel ---------------------------------------------------------------
	queuePanel = UIKit.panel({
		Name = "Queue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(460, 104),
		Visible = false,
		Parent = root,
	})
	queueTitle = UIKit.text({
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.new(1, -180, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = THEME.FontHeavy,
		Parent = queuePanel,
	})
	queueStatus = UIKit.text({
		Position = UDim2.fromOffset(18, 40),
		Size = UDim2.new(1, -180, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = THEME.Text,
		Font = THEME.FontBody,
		Parent = queuePanel,
	})
	readable(queueStatus, 13, 18)
	queueKeys = UIKit.text({
		Position = UDim2.fromOffset(18, 78),
		Size = UDim2.new(1, -180, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.TextDim,
		Font = THEME.FontBody,
		Parent = queuePanel,
	})
	readable(queueKeys, 12, 15)
	leaveButton = UIKit.new("TextButton", {
		Name = "Leave",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(140, 60),
		BackgroundColor3 = THEME.Away,
		Text = "LEAVE",
		TextColor3 = THEME.Text,
		Font = THEME.FontHeavy,
		TextSize = 22,
		Selectable = false,
		Parent = queuePanel,
	}, { UIKit.corner(12) })

	-- Results -------------------------------------------------------------------
	results = UIKit.panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(460, 230),
		Visible = false,
		Parent = root,
	})
	UIKit.gradient(THEME.PanelLight, THEME.Panel).Parent = results
	resultsTitle = UIKit.text({
		Position = UDim2.fromOffset(20, 18),
		Size = UDim2.new(1, -40, 0, 70),
		Font = THEME.FontHeavy,
		Parent = results,
	})
	resultsScore = UIKit.text({
		Position = UDim2.fromOffset(20, 96),
		Size = UDim2.new(1, -40, 0, 54),
		Font = THEME.FontHeavy,
		Parent = results,
	})
	resultsReason = UIKit.text({
		Position = UDim2.fromOffset(20, 158),
		Size = UDim2.new(1, -40, 0, 24),
		TextColor3 = THEME.TextDim,
		Font = THEME.FontBody,
		Parent = results,
	})
	readable(resultsReason, 14, 20)
	UIKit.text({
		Position = UDim2.fromOffset(20, 192),
		Size = UDim2.new(1, -40, 0, 18),
		TextColor3 = THEME.TextDim,
		Font = THEME.FontBody,
		Text = "Returning to the park…",
		Parent = results,
	})

	-- Hint ----------------------------------------------------------------------
	hint = UIKit.text({
		Name = "Hint",
		Font = THEME.Font,
		TextStrokeTransparency = 0.55,
		Parent = root,
	})
	readable(hint, 13, 20)

	local scaledElements: { GuiObject } = { scoreboard, banner, toastHolder, queuePanel, results, hint }
	for _, element in scaledElements do
		table.insert(scales, UIKit.new("UIScale", { Parent = element }))
	end
end

local function layoutForDevice()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local touch = UserInputService.TouchEnabled
	-- Phones get a higher floor so text stays readable
	local minScale = if touch then 0.72 else 0.55
	local scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), minScale, 1.25)
	for _, uiScale in scales do
		uiScale.Scale = scale
	end
	-- Keep the banner below the scoreboard row (scoreboard + shot clock /
	-- leave-match row) on short screens, and the toasts below the banner
	local scoreboardBottom = 66 + (68 + 6 + 28) * scale
	local bannerY = math.max(0.36 * viewport.Y, scoreboardBottom + 55 * scale + 6)
	banner.Position = UDim2.new(0.5, 0, 0, bannerY)
	local toastY = math.max(0.56 * viewport.Y, bannerY + (55 + 34) * scale + 6)
	toastHolder.Position = UDim2.new(0.5, 0, 0, toastY)
	local hintTop = viewport.Y - (14 + 40 * scale) - 4
	maxToasts = if toastY + 126 * scale > hintTop then 2 else 3
	-- Results panel sits below the scoreboard (which stays visible at game over)
	local resultsTop = 66 + (68 + 6) * scale + 6
	results.Position = UDim2.new(0.5, 0, 0, math.max(0.45 * viewport.Y, resultsTop + 115 * scale))
	if touch then
		-- Bottom-left is the thumbstick on phones; keep the hint between the sticks
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -14)
		hint.Size = UDim2.fromOffset(380, 40)
		hint.TextXAlignment = Enum.TextXAlignment.Center
	else
		hint.AnchorPoint = Vector2.new(0, 1)
		hint.Position = UDim2.new(0, 20, 1, -18)
		hint.Size = UDim2.fromOffset(560, 40)
		hint.TextXAlignment = Enum.TextXAlignment.Left
	end
end

function Hud.Toast(text: string, color: Color3?, seconds: number?)
	-- Keep only the newest few
	local existing = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #existing - (maxToasts - 1) do
		existing[i]:Destroy()
	end

	toastCount += 1
	local pill = UIKit.panel({
		Size = UDim2.fromOffset(380, 38),
		BackgroundTransparency = 0.08,
		LayoutOrder = toastCount,
		Parent = toastHolder,
	})
	local label = UIKit.text({
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		Text = text,
		TextColor3 = color or THEME.Text,
		Font = THEME.FontHeavy,
		Parent = pill,
	})
	task.delay(seconds or 2.2, function()
		if pill.Parent then
			UIKit.tween(pill, 0.3, { BackgroundTransparency = 1 })
			UIKit.tween(label, 0.3, { TextTransparency = 1 })
			task.wait(0.3)
			pill:Destroy()
		end
	end)
end

local function showBanner(text: string, sub: string?, color: Color3?, seconds: number?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = color or THEME.Text
	bannerSub.Text = sub or ""
	banner.Visible = true
	banner.Size = UDim2.fromOffset(560, 88)
	UIKit.tween(banner, 0.35, { Size = UDim2.fromOffset(700, 110) }, Enum.EasingStyle.Back)
	if seconds then
		task.delay(seconds, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end
end

local function hideBanner()
	bannerToken += 1
	banner.Visible = false
end

local function leaveMatchLabel(): string
	return if inputKind() == "Gamepad" then "LEAVE MATCH (D-PAD ↓)" else "LEAVE MATCH"
end

local function resetLeaveConfirm()
	confirmPending = false
	confirmToken += 1
	leaveMatchButton.Text = leaveMatchLabel()
	leaveMatchButton.TextColor3 = THEME.TextDim
end

-- First press arms, second press within 3 s forfeits
local function pressLeaveMatch()
	if confirmPending then
		resetLeaveConfirm()
		leaveMatch:FireServer()
		return
	end
	confirmPending = true
	confirmToken += 1
	local token = confirmToken
	leaveMatchButton.Text = if inputKind() == "Gamepad" then "PRESS ↓ AGAIN TO FORFEIT" else "PRESS AGAIN TO FORFEIT"
	leaveMatchButton.TextColor3 = THEME.Bad
	Hud.Toast("Press again to forfeit the match", THEME.Bad, 2.5)
	task.delay(3, function()
		if token == confirmToken then
			resetLeaveConfirm()
		end
	end)
end

local function bindAction(name: string, shouldBind: boolean, isBound: boolean, handler: () -> (), ...: Enum.KeyCode): boolean
	if shouldBind == isBound then
		return isBound
	end
	if shouldBind then
		ContextActionService:BindAction(name, function(_, state)
			if state == Enum.UserInputState.Begin then
				handler()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, ...)
	else
		ContextActionService:UnbindAction(name)
	end
	return shouldBind
end

local function anyCourtOpen(): boolean
	for _, court in MatchClient.GetCourts() do
		if court:GetAttribute("State") == "Idle" then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Refresh from attributes
--------------------------------------------------------------------------------

local REASON_TEXT = {
	Time = "Time expired",
	Overtime = "Overtime winner",
	Draw = "Overtime limit reached",
	Cancelled = "A player left before tip-off",
}

local function refresh()
	local court, role, side = MatchClient.GetMyCourt()
	local state = if court then attrString(court, "State") else ""
	local kind = inputKind()

	-- Queue panel
	local queued = role == "Queued" and court ~= nil
	queuePanel.Visible = queued
	leaveQueueBound = bindAction(LEAVE_QUEUE_ACTION, queued, leaveQueueBound, function()
		leaveQueue:FireServer()
	end, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	if queued and court then
		queueTitle.Text = ("%s · %s PAD"):format(attrString(court, "DisplayName"), (side or ""):upper())
		local otherId = attrNumber(court, if side == "Home" then "PadAwayUserId" else "PadHomeUserId")
		if otherId ~= 0 then
			local other = Players:GetPlayerByUserId(otherId)
			queueStatus.Text = ("Opponent: %s — get ready!"):format(if other then other.DisplayName else "Player")
		else
			queueStatus.Text = "Waiting for an opponent on the other pad…"
		end
		queueKeys.Text = if kind == "Gamepad" then "Press B (○) to leave" elseif kind == "Keyboard" then "Backspace or LEAVE to leave" else ""
	end

	-- Scoreboard
	local playing = role == "Playing" and court ~= nil
	scoreboard.Visible = playing
	local canLeaveMatch = playing and state ~= "GameOver"
	leaveMatchButton.Visible = canLeaveMatch
	if not canLeaveMatch and confirmPending then
		resetLeaveConfirm()
	elseif not confirmPending then
		leaveMatchButton.Text = leaveMatchLabel()
	end
	leaveMatchBound = bindAction(LEAVE_MATCH_ACTION, canLeaveMatch, leaveMatchBound, pressLeaveMatch, Enum.KeyCode.DPadDown)
	if playing and court then
		homeName.Text = attrString(court, "HomeName")
		awayName.Text = attrString(court, "AwayName")
		homeScore.Text = tostring(attrNumber(court, "HomeScore"))
		awayScore.Text = tostring(attrNumber(court, "AwayScore"))
		homeName.TextColor3 = if side == "Home" then THEME.Text else THEME.TextDim
		awayName.TextColor3 = if side == "Away" then THEME.Text else THEME.TextDim
		local ball = MatchClient.GetBall(court)
		local holder = if ball then ball:GetAttribute("HolderUserId") else 0
		homeBall.Visible = holder ~= 0 and holder == attrNumber(court, "HomeUserId")
		awayBall.Visible = holder ~= 0 and holder == attrNumber(court, "AwayUserId")
		if court:GetAttribute("Overtime") == true then
			subLabel.Text = "OVERTIME · NEXT BASKET"
		else
			subLabel.Text = ("FIRST TO %d"):format(attrNumber(court, "TargetScore"))
		end
	end

	-- Results
	if playing and court and state == "GameOver" then
		local winner = attrNumber(court, "WinnerUserId")
		local reason = attrString(court, "ResultReason")
		results.Visible = true
		if winner == 0 then
			resultsTitle.Text = if reason == "Draw" then "DRAW" else "MATCH CANCELLED"
			resultsTitle.TextColor3 = THEME.TextDim
		elseif winner == player.UserId then
			resultsTitle.Text = "VICTORY"
			resultsTitle.TextColor3 = THEME.Perfect
		else
			resultsTitle.Text = "DEFEAT"
			resultsTitle.TextColor3 = THEME.Bad
		end
		resultsScore.Text = ("%s  %d – %d  %s"):format(attrString(court, "HomeName"), attrNumber(court, "HomeScore"), attrNumber(court, "AwayScore"), attrString(court, "AwayName"))
		if reason == "Score" then
			resultsReason.Text = ("First to %d"):format(attrNumber(court, "TargetScore"))
		elseif reason == "Forfeit" then
			resultsReason.Text = if winner == player.UserId then "Opponent forfeited" else "You forfeited"
		else
			resultsReason.Text = REASON_TEXT[reason] or reason
		end
	else
		results.Visible = false
	end

	-- Banners driven by state changes (and by the dead-ball message, which can
	-- change while the state stays Dead, e.g. "WAITING FOR PLAYER")
	if state ~= lastState then
		local previous = lastState
		lastState = state
		lastCountdown = -1
		if playing and court then
			if state == "Live" and (previous == "Countdown" or previous == "Check") then
				showBanner(if previous == "Countdown" then "GO!" else "BALL IN", nil, THEME.Accent, 0.9)
			elseif state == "Check" then
				showBanner("CHECK", "Get set…", THEME.TextDim, Config.Match.CheckTime)
			elseif state == "GameOver" then
				hideBanner()
			end
		elseif previous == "GameOver" or previous == "Live" or previous == "Dead" then
			hideBanner()
		end
	end
	if playing and court and state == "Dead" then
		local message = attrString(court, "Message")
		if message ~= "" and message ~= lastBannerMessage then
			lastBannerMessage = message
			showBanner(message, nil, THEME.Text, nil)
		end
	else
		lastBannerMessage = ""
	end

	-- Hint
	if playing then
		if MatchClient.CanShootNow() then
			hint.Text = ("%s · release in the green to shoot · %s"):format(shootPrompt(), crossoverPrompt())
		elseif MatchClient.CanStealNow() then
			hint.Text = "Defense · " .. defensePrompt()
		else
			hint.Text = ""
		end
	elseif queued then
		hint.Text = ""
	elseif MatchClient.GetHeldBall() then
		hint.Text = ("Practice · %s · release in the green to shoot · %s"):format(shootPrompt(), crossoverPrompt())
	elseif not anyCourtOpen() and #MatchClient.GetCourts() > 0 then
		hint.Text = "All courts are in a match — the pads light up again when one opens"
	else
		hint.Text = "Step onto a glowing pad to queue for 1v1 · Grab a court ball to practice"
	end
end

-- Runs every frame, but only touches text that changes (clocks + countdowns)
local function tick()
	local court, role = MatchClient.GetMyCourt()
	if not court then
		return
	end
	local serverNow = workspace:GetServerTimeNow()
	if role == "Playing" then
		local state = attrString(court, "State")
		local endsAt = attrNumber(court, "ClockEndsAt")
		local remaining = if endsAt > 0 then endsAt - serverNow else attrNumber(court, "ClockRemaining")
		local text = if court:GetAttribute("Overtime") == true then "OT" else UIKit.formatClock(remaining)
		if clockLabel.Text ~= text then
			clockLabel.Text = text
		end

		local shotEndsAt = attrNumber(court, "ShotClockEndsAt")
		local showShot = state == "Live" and shotEndsAt > 0
		shotClock.Visible = showShot
		if showShot then
			local left = math.max(0, math.ceil(shotEndsAt - serverNow))
			local shotText = ("SHOT %d"):format(left)
			if shotClockLabel.Text ~= shotText then
				shotClockLabel.Text = shotText
				shotClockLabel.TextColor3 = if left <= 5 then THEME.Bad else THEME.Text
			end
		end

		if state == "Countdown" then
			local left = math.ceil(attrNumber(court, "PhaseEndsAt") - serverNow)
			if left ~= lastCountdown and left > 0 then
				lastCountdown = left
				showBanner(tostring(left), "1V1 · " .. attrString(court, "DisplayName"), THEME.Text, nil)
			end
		end
	elseif role == "Queued" then
		local readyAt = attrNumber(court, "QueueReadyAt")
		if readyAt > 0 then
			local text = ("Match starting in %d…"):format(math.max(0, math.ceil(readyAt - serverNow)))
			if queueStatus.Text ~= text then
				queueStatus.Text = text
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Feedback events from the server
--------------------------------------------------------------------------------

local SCORE_WORDS = { [2] = "BUCKET!", [3] = "SPLASH!" }

local function onFeedback(kind: string, data: any)
	if typeof(data) ~= "table" then
		data = {}
	end
	if kind == "Release" then
		if data.Quality == "Perfect" then
			Hud.Toast("PERFECT RELEASE", THEME.Perfect, 1.4)
		end
	elseif kind == "Score" then
		local points = tonumber(data.Points) or 0
		if data.ShooterUserId == player.UserId then
			local word = SCORE_WORDS[points] or "SCORE!"
			if data.Practice then
				Hud.Toast(("+%d  %s  (practice)"):format(points, word), THEME.Accent, 1.6)
			else
				Hud.Toast(("+%d  %s"):format(points, word), THEME.Perfect, 1.8)
			end
		else
			Hud.Toast(("Opponent scored +%d"):format(points), THEME.Bad, 1.6)
		end
	elseif kind == "Steal" then
		if data.Success == true then
			if data.StealerUserId == player.UserId then
				showBanner("STEAL!", nil, THEME.Perfect, 1)
			else
				showBanner("STRIPPED!", nil, THEME.Bad, 1)
			end
		elseif data.StealerUserId == player.UserId then
			local reason = if typeof(data.Reason) == "string" then data.Reason else "Missed"
			Hud.Toast(("%s — slowed for a moment"):format(reason), THEME.Bad, 1.2)
		end
	elseif kind == "Block" then
		if data.BlockerUserId == player.UserId then
			showBanner("BLOCKED!", nil, THEME.Perfect, 1)
		else
			showBanner("REJECTED!", nil, THEME.Bad, 1)
		end
	elseif kind == "Ankles" then
		if data.HandlerUserId == player.UserId then
			showBanner("ANKLES BROKEN!", "They bit on the crossover", THEME.Perfect, 1.2)
		else
			showBanner("ANKLES!", "You reached on a crossover", THEME.Bad, 1.2)
		end
	elseif kind == "Turnover" then
		local reason = if typeof(data.Reason) == "string" then data.Reason else "Turnover"
		if data.LastTouchUserId == player.UserId then
			Hud.Toast(("%s — their ball"):format(reason), THEME.Bad, 1.8)
		else
			Hud.Toast(("%s — your ball!"):format(reason), THEME.Good, 1.8)
		end
	elseif kind == "Overtime" then
		showBanner("OVERTIME", "Next basket wins", THEME.Accent, 2)
	elseif kind == "MatchStarting" then
		Hud.Toast("Match found — 1v1!", THEME.Accent, 2)
	elseif kind == "ShotRejected" then
		if typeof(data.Reason) == "string" and data.Reason ~= "" then
			Hud.Toast(data.Reason, THEME.Bad, 2)
		end
	elseif kind == "Notice" then
		if typeof(data.Text) == "string" then
			Hud.Toast(data.Text, THEME.TextDim, 2.5)
		end
	end
	-- "MatchEnded": the results screen is driven by attributes
end

--------------------------------------------------------------------------------

function Hud.Init()
	leaveQueue = Net.Event("LeaveQueue")
	leaveMatch = Net.Event("LeaveMatch")
	build()
	layoutForDevice()
	leaveButton.Activated:Connect(function()
		leaveQueue:FireServer()
	end)
	leaveMatchButton.Activated:Connect(pressLeaveMatch)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutForDevice)
	end
	MatchClient.Changed:Connect(refresh)
	UserInputService.LastInputTypeChanged:Connect(refresh)
	Net.Event("Feedback").OnClientEvent:Connect(onFeedback)
	RunService.RenderStepped:Connect(tick)
	refresh()
end

return Hud
