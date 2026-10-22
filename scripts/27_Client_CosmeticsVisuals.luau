--!strict
-- CosmeticsVisuals (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > CosmeticsVisuals
-- Shows other players' (and your own) cosmetics on this screen: the ball skin
-- of whoever has the ball (and the trail behind their shots), and the scorer's
-- effect at the rim when a shot goes in. It reads what the server published on
-- each Player (Equipped<Slot>); nothing here affects gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent
local MatchClient = require(Client:WaitForChild("MatchClient"))

local CosmeticsVisuals = {}
CosmeticsVisuals.ScriptVersion = 1 -- ClientMain compares this to spot an old copy; bump when this file changes
CosmeticsVisuals.ScriptFile = "27_Client_CosmeticsVisuals" -- and this to spot another file's code pasted here

local COSMETICS = Config.Cosmetics
local EFFECT_RANGE = 250 -- don't bother with effects farther than this from the camera
local TEXTURES = {
	Sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local items: { [string]: Config.CosmeticItem } = {}
for _, item in COSMETICS.Items do
	items[item.Id] = item
end

-- Per ball (by court id, one ball per court)
type BallState = {
	Owner: number, -- whose skin it shows: the holder, or the last one
	Skin: string, -- the skin applied right now
	Shooter: number, -- who last held it (for the score effect in practice)
	State: string,
	Home: number, -- the court's scores last frame (for the score effect in a match)
	Away: number,
	Trail: Trail?,
}
local balls: { [string]: BallState } = {}
local effectsFolder: Folder? = nil

local function equipped(userId: number, slot: string): Config.CosmeticItem?
	local who = if userId ~= 0 then Players:GetPlayerByUserId(userId) else nil
	local id = who and who:GetAttribute("Equipped" .. slot)
	if typeof(id) == "string" and id ~= "" then
		local item = items[id]
		if item and item.Slot == slot then
			return item
		end
	end
	return nil
end

local function attrNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

--------------------------------------------------------------------------------
-- Ball skins and shot trails
--------------------------------------------------------------------------------

local function applySkin(ball: BasePart, skin: Config.CosmeticItem)
	ball.Color = skin.Color or Config.Ball.Color
	ball.Material = skin.Material or Enum.Material.SmoothPlastic
	for _, child in ball:GetChildren() do
		if child.Name == "Seam" and child:IsA("BasePart") then
			child.Color = skin.Accent or Config.Ball.SeamColor
		end
	end
end

local function trailFor(ball: BasePart, state: BallState): Trail
	local trail = state.Trail
	if trail and trail.Parent == ball then
		return trail
	end
	local radius = Config.Ball.Radius
	local top = Instance.new("Attachment")
	top.Name = "SkinTrailTop"
	top.Position = Vector3.new(0, radius * 0.6, 0)
	top.Parent = ball
	local bottom = Instance.new("Attachment")
	bottom.Name = "SkinTrailBottom"
	bottom.Position = Vector3.new(0, -radius * 0.6, 0)
	bottom.Parent = ball
	local newTrail = Instance.new("Trail")
	newTrail.Name = "SkinTrail"
	newTrail.Attachment0 = top
	newTrail.Attachment1 = bottom
	newTrail.Lifetime = 0.35
	newTrail.MinLength = 0.05
	newTrail.LightEmission = 0.6
	newTrail.FaceCamera = true
	newTrail.Transparency = NumberSequence.new(0.15, 1)
	newTrail.Enabled = false
	newTrail.Parent = ball
	state.Trail = newTrail
	return newTrail
end

--------------------------------------------------------------------------------
-- Score effects: a short burst at the rim
--------------------------------------------------------------------------------

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Enabled = false
	for key, value in props do
		(particles :: any)[key] = value
	end
	particles.Parent = parent
	return particles
end

local function playEffect(effect: Config.CosmeticItem, at: Vector3)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude > EFFECT_RANGE then
		return
	end
	if not effectsFolder or effectsFolder.Parent == nil then
		local folder = Instance.new("Folder")
		folder.Name = "StreetHoopsEffects"
		folder.Parent = workspace
		effectsFolder = folder
	end
	local anchor = Instance.new("Part")
	anchor.Name = effect.Id
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = effectsFolder
	local main, second = effect.Color or Color3.new(1, 1, 1), effect.Accent or Color3.new(1, 1, 1)
	local style = effect.Effect

	if style == "Confetti" then
		emitter(anchor, {
			Texture = TEXTURES.Sparkles,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, main),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 60)),
				ColorSequenceKeypoint.new(1, second),
			}),
			Size = NumberSequence.new(0.45),
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(16, 26),
			SpreadAngle = Vector2.new(35, 35),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -28, 0),
			Drag = 1.5,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
		}):Emit(90)
	elseif style == "Fire" then
		local flames = emitter(anchor, {
			Texture = TEXTURES.Fire,
			Color = ColorSequence.new(second, main),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.4) }),
			Transparency = NumberSequence.new(0.1, 1),
			Lifetime = NumberRange.new(0.6, 0.9),
			Speed = NumberRange.new(5, 9),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top,
			LightEmission = 0.8,
			Rate = 70,
		})
		flames.Enabled = true
		task.delay(1.1, function()
			flames.Enabled = false
		end)
		local light = Instance.new("PointLight")
		light.Color = main
		light.Brightness = 3
		light.Range = 14
		light.Parent = anchor
	elseif style == "Lightning" then
		emitter(anchor, {
			Texture = TEXTURES.Sparkles,
			Color = ColorSequence.new(second, main),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.25, 0.45),
			Speed = NumberRange.new(28, 40),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		}):Emit(70)
		local light = Instance.new("PointLight")
		light.Color = main
		light.Brightness = 8
		light.Range = 22
		light.Parent = anchor
		task.delay(0.12, function()
			light.Brightness = 2
		end)
		task.delay(0.22, function()
			light.Brightness = 6
		end)
		task.delay(0.35, function()
			light.Enabled = false
		end)
	else -- Sparks
		emitter(anchor, {
			Texture = TEXTURES.Sparkles,
			Color = ColorSequence.new(main, second),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(12, 20),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		}):Emit(60)
	end
	task.delay(3, function()
		anchor:Destroy()
	end)
end

--------------------------------------------------------------------------------

local function step()
	local seen: { [string]: boolean } = {}
	for _, court in MatchClient.GetCourts() do
		local ball = MatchClient.GetBall(court)
		if not ball or court.Parent == nil then
			continue
		end
		local courtId = court:GetAttribute("CourtId")
		if typeof(courtId) ~= "string" then
			continue
		end
		seen[courtId] = true
		local state = balls[courtId]
		local ballState = ball:GetAttribute("State")
		local now = if typeof(ballState) == "string" then ballState else ""
		local home, away = attrNumber(court, "HomeScore"), attrNumber(court, "AwayScore")
		if not state then
			state = { Owner = 0, Skin = "", Shooter = 0, State = now, Home = home, Away = away, Trail = nil }
			balls[courtId] = state
		end
		local holder = attrNumber(ball, "HolderUserId")
		if holder ~= 0 then
			state.Owner = holder
			if now == "Held" then
				state.Shooter = holder
			end
		end

		-- The skin of whoever has it (or had it last); everyone else's look stays put
		local skin = equipped(state.Owner, "Ball") or items[COSMETICS.DefaultBall]
		local trail = trailFor(ball, state)
		if skin and skin.Id ~= state.Skin then
			state.Skin = skin.Id
			applySkin(ball, skin)
			if skin.Trail then
				trail.Color = ColorSequence.new(skin.Trail)
			end
		end
		local showTrail = now == "InFlight" and skin ~= nil and skin.Trail ~= nil
		if trail.Enabled ~= showTrail then
			trail.Enabled = showTrail
		end

		-- A basket: the scorer's effect at the rim. In a match that's a score going
		-- up (the ball skips straight past "Scored" on a game-winner); in practice,
		-- the ball dropping in.
		local scorer = 0
		if court:GetAttribute("State") ~= "Idle" then
			if home > state.Home then
				scorer = attrNumber(court, "HomeUserId")
			elseif away > state.Away then
				scorer = attrNumber(court, "AwayUserId")
			end
		elseif now == "Scored" and state.State ~= "Scored" then
			scorer = state.Shooter
		end
		state.State, state.Home, state.Away = now, home, away
		local effect = if scorer ~= 0 then equipped(scorer, "Effect") else nil
		local rim = court:GetAttribute("RimCenter")
		if effect and typeof(rim) == "Vector3" then
			playEffect(effect, rim)
		end
	end
	for courtId in balls do
		if not seen[courtId] then
			balls[courtId] = nil
		end
	end
end

function CosmeticsVisuals.Init()
	RunService.Heartbeat:Connect(step)
end

return CosmeticsVisuals
