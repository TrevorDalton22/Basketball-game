--!strict
-- CourtBuilder (ModuleScript) — ServerScriptService > Server > CourtBuilder
-- Builds the street park and every court from Config at server start, so the
-- map is reproducible and all gameplay geometry matches Config exactly.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BasketballMath = require(Shared:WaitForChild("BasketballMath"))

local CourtBuilder = {}

export type CourtHandle = {
	Id: string,
	DisplayName: string,
	Model: Model,
	Origin: CFrame,
	RimCenter: Vector3,
	Pads: { Home: BasePart, Away: BasePart },
	PadLabels: { Home: TextLabel, Away: TextLabel },
	SignLabel: TextLabel,
	RackPosition: Vector3,
	ReturnSpots: { Home: CFrame, Away: CFrame },
}

local C = Config.Court

local PALETTE = {
	Grass = Color3.fromRGB(88, 140, 72),
	Plaza = Color3.fromRGB(168, 164, 156),
	Runoff = Color3.fromRGB(34, 52, 74),
	Court = Color3.fromRGB(38, 94, 160),
	Key = Color3.fromRGB(214, 98, 44),
	Line = Color3.fromRGB(246, 246, 240),
	Metal = Color3.fromRGB(46, 50, 58),
	Padding = Color3.fromRGB(30, 80, 160),
	Rim = Color3.fromRGB(235, 82, 38),
	Board = Color3.fromRGB(220, 235, 245),
	Wood = Color3.fromRGB(150, 104, 64),
	Trunk = Color3.fromRGB(104, 76, 52),
	Leaves = Color3.fromRGB(62, 120, 58),
	Fence = Color3.fromRGB(120, 126, 134),
}

local function make<T>(className: string, props: { [string]: any }, parent: Instance?): T
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return (instance :: any) :: T
end

-- Anchored static part with sensible defaults
local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
	local part = make("Part", {
		Name = name,
		Anchored = true,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent) :: Part
	if extra then
		for key, value in extra do
			(part :: any)[key] = value
		end
	end
	return part
end

local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

-- Props outside the raised court slab stand on the plaza (world y ≈ 0.1).
-- In court-local space (origin is at the court floor top) that is this height:
local GROUND = 0.1 - C.FloorTop

local function cylinderVertical(parent: Instance, name: string, height: number, diameter: number, bottomCenter: CFrame, color: Color3, material: Enum.Material?): Part
	local cf = bottomCenter * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	local part = block(parent, name, Vector3.new(height, diameter, diameter), cf, color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Thin decorative strip between two world points (used for court lines and nets)
-- `height` is measured along `upHint` (default world up), `width` across it.
local function strip(parent: Instance, a: Vector3, b: Vector3, width: number, height: number, color: Color3, extraLength: number?, upHint: Vector3?): Part?
	local delta = b - a
	local length = delta.Magnitude
	if length < 1e-3 then
		return nil
	end
	local mid = (a + b) / 2
	local up = upHint or (if math.abs(delta.Unit.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis)
	local cf = CFrame.lookAt(mid, b, up)
	return block(parent, "Line", Vector3.new(width, height, length + (extraLength or 0)), cf, color, Enum.Material.SmoothPlastic, DECOR)
end

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font): TextLabel
	local gui = make("SurfaceGui", {
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
		Brightness = 1.5,
	}, part) :: SurfaceGui
	local label = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		Font = font,
		TextScaled = true,
	}, gui) :: TextLabel
	make("UIPadding", {
		PaddingLeft = UDim.new(0.04, 0),
		PaddingRight = UDim.new(0.04, 0),
		PaddingTop = UDim.new(0.08, 0),
		PaddingBottom = UDim.new(0.08, 0),
	}, label)
	return label
end

--------------------------------------------------------------------------------
-- Lighting and park
--------------------------------------------------------------------------------

local function setupLighting()
	Lighting.ClockTime = 17.4
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 110, 130)
	Lighting.ShadowSoftness = 0.25

	local function ensure(className: string, props: { [string]: any })
		-- The Baseplate template already has some of these; restyle them instead
		local existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			for key, value in props do
				(existing :: any)[key] = value
			end
			return
		end
		make(className, props, Lighting)
	end
	ensure("Atmosphere", { Density = 0.28, Offset = 0.15, Color = Color3.fromRGB(255, 214, 180), Decay = Color3.fromRGB(120, 90, 110), Glare = 0.4, Haze = 1.4 })
	ensure("BloomEffect", { Intensity = 0.6, Size = 28, Threshold = 1.6 })
	ensure("ColorCorrectionEffect", { Saturation = 0.12, Contrast = 0.06, TintColor = Color3.fromRGB(255, 246, 236) })
	ensure("SunRaysEffect", { Intensity = 0.06, Spread = 0.8 })
end

local function tree(parent: Instance, position: Vector3, scale: number)
	local base = CFrame.new(position)
	cylinderVertical(parent, "Trunk", 9 * scale, 1.4 * scale, base, PALETTE.Trunk, Enum.Material.Wood)
	local leaves = block(parent, "Leaves", Vector3.new(9, 9, 9) * scale, base * CFrame.new(0, 11 * scale, 0), PALETTE.Leaves, Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
	local top = block(parent, "Leaves", Vector3.new(6, 6, 6) * scale, base * CFrame.new(1.2 * scale, 15 * scale, 0.8 * scale), PALETTE.Leaves:Lerp(Color3.new(1, 1, 0.6), 0.1), Enum.Material.Grass)
	top.Shape = Enum.PartType.Ball
end

local function bench(parent: Instance, cframe: CFrame)
	block(parent, "Seat", Vector3.new(8, 0.4, 1.8), cframe * CFrame.new(0, 1.8, 0), PALETTE.Wood, Enum.Material.WoodPlanks)
	block(parent, "Back", Vector3.new(8, 1.6, 0.3), cframe * CFrame.new(0, 3, 0.85), PALETTE.Wood, Enum.Material.WoodPlanks)
	for _, x in { -3.4, 3.4 } do
		block(parent, "Leg", Vector3.new(0.4, 1.6, 1.6), cframe * CFrame.new(x, 0.8, 0), PALETTE.Metal, Enum.Material.Metal)
	end
end

local function lightPole(parent: Instance, base: CFrame, target: Vector3)
	cylinderVertical(parent, "LightPole", 22, 0.8, base, PALETTE.Metal, Enum.Material.Metal)
	local headPos = base.Position + Vector3.new(0, 22.4, 0)
	local head = block(parent, "LightHead", Vector3.new(3, 0.8, 2), CFrame.lookAt(headPos, Vector3.new(target.X, headPos.Y, target.Z)), PALETTE.Metal, Enum.Material.Metal)
	block(head, "Lamp", Vector3.new(2.6, 0.2, 1.6), head.CFrame * CFrame.new(0, -0.45, 0), Color3.fromRGB(255, 244, 214), Enum.Material.Neon, DECOR)
	local attachment = make("Attachment", {}, head) :: Attachment
	attachment.WorldCFrame = CFrame.lookAt(head.Position, target)
	make("SpotLight", {
		Face = Enum.NormalId.Front,
		Angle = 75,
		Range = 60,
		Brightness = 2.2,
		Color = Color3.fromRGB(255, 236, 205),
		Shadows = true,
	}, attachment)
end

local function buildPark(parkFolder: Folder, anchor: CFrame)
	block(parkFolder, "Ground", Vector3.new(700, 2, 700), CFrame.new(anchor.Position.X, -1, anchor.Position.Z + 30), PALETTE.Grass, Enum.Material.Grass)

	-- Concrete plaza under the courts and lobby
	local plazaDepth = C.Length + C.Runoff * 2 + 60
	local plazaWidth = C.Width + C.Runoff * 2 + 36
	local plazaCenter = anchor * CFrame.new(0, -anchor.Position.Y + 0.05, C.Length / 2 + 22)
	block(parkFolder, "Plaza", Vector3.new(plazaWidth, 0.1, plazaDepth), plazaCenter, PALETTE.Plaza, Enum.Material.Concrete)

	-- Spawn in the lobby, facing the court
	local spawnPos = anchor:PointToWorldSpace(Config.Lobby.SpawnOffset)
	local spawnCF = CFrame.lookAt(Vector3.new(spawnPos.X, 0.5, spawnPos.Z), Vector3.new(anchor.Position.X, 0.5, anchor.Position.Z))
	local spawn = make("SpawnLocation", {
		Name = "LobbySpawn",
		Anchored = true,
		Size = Vector3.new(12, 1, 12),
		CFrame = spawnCF,
		Color = Config.UI.Accent,
		Material = Enum.Material.SmoothPlastic,
		Neutral = true,
		Duration = 0,
		TopSurface = Enum.SurfaceType.Smooth,
	}, parkFolder) :: SpawnLocation
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy() -- remove the default spawn logo
	end

	-- Entrance arch on the walkway from the spawn to the court
	local archCF = spawnCF * CFrame.new(0, -0.5, -6)
	for _, x in { -12, 12 } do
		block(parkFolder, "ArchPillar", Vector3.new(2, 16, 2), archCF * CFrame.new(x, 8, 0), PALETTE.Metal, Enum.Material.Metal)
	end
	local beam = block(parkFolder, "ArchSign", Vector3.new(26, 3.5, 1), archCF * CFrame.new(0, 17, 0), Config.UI.Panel, Enum.Material.SmoothPlastic)
	surfaceText(beam, Enum.NormalId.Back, "STREET HOOPS", Config.UI.Accent, Config.UI.FontHeavy)
	surfaceText(beam, Enum.NormalId.Front, "STREET HOOPS", Config.UI.Accent, Config.UI.FontHeavy)

	-- Benches and trees around the lobby
	-- Benches either side of the spawn, facing it
	bench(parkFolder, spawnCF * CFrame.new(-16, -0.4, 0) * CFrame.Angles(0, math.rad(-90), 0))
	bench(parkFolder, spawnCF * CFrame.new(16, -0.4, 0) * CFrame.Angles(0, math.rad(90), 0))
	local treeSpots = {
		Vector3.new(-50, 0, 10), Vector3.new(50, 0, 14), Vector3.new(-56, 0, -30),
		Vector3.new(58, 0, -26), Vector3.new(-48, 0, 70), Vector3.new(52, 0, 74),
		Vector3.new(-30, 0, 96), Vector3.new(30, 0, 98), Vector3.new(-70, 0, 40),
		Vector3.new(72, 0, 44), Vector3.new(0, 0, -40), Vector3.new(-24, 0, -42),
		Vector3.new(26, 0, -44),
	}
	for i, offset in treeSpots do
		local p = anchor:PointToWorldSpace(offset)
		tree(parkFolder, Vector3.new(p.X, 0, p.Z), 0.9 + (i % 3) * 0.15)
	end
end

--------------------------------------------------------------------------------
-- Court
--------------------------------------------------------------------------------

local function courtLines(folder: Instance, origin: CFrame)
	-- Layers: surface top 0.03, key paint top 0.06, lines 0.06–0.09
	local y = 0.075
	local w = C.LineWidth
	local function P(x: number, z: number): Vector3
		return origin:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local function line(x1: number, z1: number, x2: number, z2: number)
		strip(folder, P(x1, z1), P(x2, z2), w, 0.03, PALETTE.Line, w)
	end
	local function arc(cx: number, cz: number, radius: number, fromDeg: number, toDeg: number, segments: number)
		local prev: Vector3? = nil
		for i = 0, segments do
			local a = math.rad(fromDeg + (toDeg - fromDeg) * i / segments)
			local point = P(cx + radius * math.sin(a), cz + radius * math.cos(a))
			if prev then
				strip(folder, prev, point, w, 0.03, PALETTE.Line, w * 0.6)
			end
			prev = point
		end
	end

	local hw = C.Width / 2
	-- Boundary
	line(-hw, 0, hw, 0)
	line(-hw, 0, -hw, C.Length)
	line(hw, 0, hw, C.Length)
	line(-hw, C.Length, hw, C.Length)
	-- Key
	local kw = C.KeyWidth / 2
	line(-kw, 0, -kw, C.FreeThrowDistance)
	line(kw, 0, kw, C.FreeThrowDistance)
	line(-kw, C.FreeThrowDistance, kw, C.FreeThrowDistance)
	arc(0, C.FreeThrowDistance, C.FreeThrowCircleRadius, -90, 90, 16)
	-- Restricted area
	arc(0, C.RimDistance, C.RestrictedRadius, -90, 90, 12)
	-- Three-point line: corner straights + arc
	local breakZ = C.RimDistance + math.sqrt(C.ThreePointRadius ^ 2 - C.CornerThreeX ^ 2)
	line(-C.CornerThreeX, 0, -C.CornerThreeX, breakZ)
	line(C.CornerThreeX, 0, C.CornerThreeX, breakZ)
	local theta = math.deg(math.asin(C.CornerThreeX / C.ThreePointRadius))
	arc(0, C.RimDistance, C.ThreePointRadius, -theta, theta, 36)
	-- Half-court circle (half of it lies on this half court)
	arc(0, C.Length, C.CenterCircleRadius, 90, 270, 16)
end

local function buildHoop(folder: Instance, origin: CFrame)
	local hoop = make("Model", { Name = "Hoop" }, folder) :: Model
	local function L(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	-- Support pole behind the baseline
	local poleZ = -3.5
	cylinderVertical(hoop, "Pole", 13, 0.9, L(0, 0, poleZ), PALETTE.Metal, Enum.Material.Metal)
	block(hoop, "PolePad", Vector3.new(1.5, 6, 1.5), L(0, 3, poleZ), PALETTE.Padding, Enum.Material.Fabric)
	local armLength = C.BackboardZ - 0.3 - poleZ
	block(hoop, "Arm", Vector3.new(0.6, 0.6, armLength), L(0, 12.4, poleZ + armLength / 2), PALETTE.Metal, Enum.Material.Metal)
	strip(hoop, L(0, 9.5, poleZ).Position, L(0, 12.2, C.BackboardZ - 1.2).Position, 0.35, 0.35, PALETTE.Metal)

	-- Backboard
	local bw, bh = C.BackboardSize.X, C.BackboardSize.Y
	local boardCenterY = C.BackboardBottom + bh / 2
	local board = block(hoop, "Backboard", Vector3.new(bw, bh, 0.3), L(0, boardCenterY, C.BackboardZ - 0.15), PALETTE.Board, Enum.Material.Glass, {
		Transparency = 0.35,
		CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.5, 1, 1),
	})
	board.CastShadow = false
	local frontZ = C.BackboardZ + 0.012
	local boardNormal = origin:VectorToWorldSpace(Vector3.zAxis)
	local function boardLine(x1: number, y1: number, x2: number, y2: number, width: number)
		-- Thin along the board normal, wide across the glass
		strip(hoop, L(x1, y1, frontZ).Position, L(x2, y2, frontZ).Position, width, 0.02, PALETTE.Line, width, boardNormal)
	end
	-- Border
	local ox, oy = bw / 2 - 0.12, bh / 2 - 0.12
	boardLine(-ox, boardCenterY - oy, ox, boardCenterY - oy, 0.24)
	boardLine(-ox, boardCenterY + oy, ox, boardCenterY + oy, 0.24)
	boardLine(-ox, boardCenterY - oy, -ox, boardCenterY + oy, 0.24)
	boardLine(ox, boardCenterY - oy, ox, boardCenterY + oy, 0.24)
	-- Shooter's square
	local sy = C.RimHeight + 0.2
	boardLine(-1.2, sy, 1.2, sy, 0.16)
	boardLine(-1.2, sy + 1.8, 1.2, sy + 1.8, 0.16)
	boardLine(-1.2, sy, -1.2, sy + 1.8, 0.16)
	boardLine(1.2, sy, 1.2, sy + 1.8, 0.16)

	-- Rim: a ring of short segments so the ball can bounce off it physically
	local ringRadius = C.RimRadius + C.RimTube / 2
	local center = Vector3.new(0, C.RimHeight, C.RimDistance)
	local segments = 20
	local segmentLength = (2 * math.pi * ringRadius / segments) * 1.12
	local rimProps = PhysicalProperties.new(2, 0.3, 0.42, 1, 3)
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local localPos = center + Vector3.new(ringRadius * math.cos(a), 0, ringRadius * math.sin(a))
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local worldPos = origin:PointToWorldSpace(localPos)
		local worldTangent = origin:VectorToWorldSpace(tangent)
		block(hoop, "Rim", Vector3.new(C.RimTube, C.RimTube, segmentLength), CFrame.lookAt(worldPos, worldPos + worldTangent), PALETTE.Rim, Enum.Material.Metal, {
			CustomPhysicalProperties = rimProps,
		})
	end
	local bracketDepth = C.RimDistance - ringRadius - C.BackboardZ
	block(hoop, "RimBracket", Vector3.new(0.7, 0.16, bracketDepth + 0.1), L(0, C.RimHeight, C.BackboardZ + bracketDepth / 2), PALETTE.Rim, Enum.Material.Metal)

	-- Net (decorative, no collision)
	local strands = 12
	local topR, bottomR, netDrop = C.RimRadius, C.RimRadius * 0.62, 1.7
	local netColor = Color3.fromRGB(250, 250, 250)
	for i = 0, strands - 1 do
		local a = i / strands * math.pi * 2
		local top = center + Vector3.new(topR * math.cos(a), -0.05, topR * math.sin(a))
		for _, twist in { 0.45, -0.45 } do
			local b = a + twist
			local bottom = center + Vector3.new(bottomR * math.cos(b), -netDrop, bottomR * math.sin(b))
			strip(hoop, origin:PointToWorldSpace(top), origin:PointToWorldSpace(bottom), 0.06, 0.06, netColor)
		end
		local nextA = (i + 1) / strands * math.pi * 2
		local b1 = center + Vector3.new(bottomR * math.cos(a), -netDrop, bottomR * math.sin(a))
		local b2 = center + Vector3.new(bottomR * math.cos(nextA), -netDrop, bottomR * math.sin(nextA))
		strip(hoop, origin:PointToWorldSpace(b1), origin:PointToWorldSpace(b2), 0.06, 0.06, netColor)
	end

	-- Hoop collision groups: a server-decided make passes cleanly through both.
	-- The ring and its bracket are "Rim" (players pass through them); the glass
	-- and supports are "Hoop". (Net strands and painted lines don't collide at all.)
	for _, descendant in hoop:GetDescendants() do
		if descendant:IsA("BasePart") then
			local isRing = descendant.Name == "Rim" or descendant.Name == "RimBracket"
			descendant.CollisionGroup = if isRing then Config.Collision.Rim else Config.Collision.Hoop
		end
	end
end

local function buildFence(folder: Instance, origin: CFrame)
	local fence = make("Model", { Name = "Fence" }, folder) :: Model
	local hw = C.Width / 2 + C.Runoff + 1
	local zBack = -C.Runoff - 1
	local zFront = C.Length + C.Runoff - 6 -- the half-court side stays open as the entrance
	local height = 9
	local function run(x1: number, z1: number, x2: number, z2: number)
		local a = Vector3.new(x1, 0, z1)
		local b = Vector3.new(x2, 0, z2)
		local length = (b - a).Magnitude
		local posts = math.max(1, math.floor(length / 8))
		for i = 0, posts do
			local p = a:Lerp(b, i / posts)
			cylinderVertical(fence, "Post", height, 0.35, origin * CFrame.new(p + Vector3.new(0, GROUND, 0)), PALETTE.Metal, Enum.Material.Metal)
		end
		for _, y in { GROUND + 0.4, GROUND + height - 0.1 } do
			strip(fence, origin:PointToWorldSpace(a + Vector3.new(0, y, 0)), origin:PointToWorldSpace(b + Vector3.new(0, y, 0)), 0.2, 0.2, PALETTE.Metal)
		end
		local mid = (a + b) / 2 + Vector3.new(0, GROUND + height / 2, 0)
		local worldMid = origin:PointToWorldSpace(mid)
		block(fence, "Mesh", Vector3.new(0.08, height - 0.6, length), CFrame.lookAt(worldMid, origin:PointToWorldSpace(b + Vector3.new(0, GROUND + height / 2, 0))), PALETTE.Fence, Enum.Material.DiamondPlate, {
			Transparency = 0.72,
			CastShadow = false,
		})
	end
	run(-hw, zBack, hw, zBack)
	run(-hw, zBack, -hw, zFront)
	run(hw, zBack, hw, zFront)
end

local function buildPad(folder: Instance, origin: CFrame, side: "Home" | "Away", localPos: Vector3, color: Color3): (Part, TextLabel)
	local size = Config.Queue.PadSize
	-- Pads sit on the plaza, slightly below the raised court floor
	local cf = origin * CFrame.new(localPos + Vector3.new(0, GROUND + 0.06, 0))
	local pad = block(folder, side .. "Pad", Vector3.new(size, 0.12, size), cf, color, Enum.Material.Neon, {
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 0.15,
	})
	pad:SetAttribute("Side", side)
	block(folder, side .. "PadBase", Vector3.new(size + 1, 0.1, size + 1), origin * CFrame.new(localPos + Vector3.new(0, GROUND + 0.02, 0)), Config.UI.Panel, Enum.Material.SmoothPlastic, DECOR)

	local billboard = make("BillboardGui", {
		Name = "PadLabel",
		Size = UDim2.fromOffset(220, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0),
		AlwaysOnTop = false,
		MaxDistance = 90,
		LightInfluence = 0,
	}, pad) :: BillboardGui
	local label = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = side == "Home" and "HOME · 1V1" or "AWAY · 1V1",
		TextColor3 = Config.UI.Text,
		TextStrokeTransparency = 0.4,
		Font = Config.UI.FontHeavy,
		TextScaled = true,
	}, billboard) :: TextLabel
	return pad, label
end

local function buildCourt(courtsFolder: Folder, def: { Id: string, DisplayName: string, Position: Vector3, Yaw: number }): CourtHandle
	local origin = BasketballMath.CourtOrigin(def.Position, def.Yaw)
	local model = make("Model", { Name = def.Id }, courtsFolder) :: Model
	model:SetAttribute("CourtId", def.Id)
	model:SetAttribute("DisplayName", def.DisplayName)
	-- Clients use this to know when they're driving at the rim (layups/dunks)
	model:SetAttribute("RimCenter", BasketballMath.RimCenter(origin))
	local static = make("Folder", { Name = "Static" }, model) :: Folder

	-- Floor: runoff slab, playing surface and painted key
	local hw = C.Width / 2
	local slabW = C.Width + C.Runoff * 2
	local slabD = C.Length + C.Runoff * 2
	local floorCF = origin * CFrame.new(0, -C.FloorThickness / 2, C.Length / 2)
	block(static, "Runoff", Vector3.new(slabW, C.FloorThickness, slabD), floorCF, PALETTE.Runoff, Enum.Material.Concrete)
	block(static, "Surface", Vector3.new(C.Width, 0.06, C.Length), origin * CFrame.new(0, 0, C.Length / 2), PALETTE.Court, Enum.Material.SmoothPlastic, DECOR)
	block(static, "Key", Vector3.new(C.KeyWidth, 0.06, C.FreeThrowDistance), origin * CFrame.new(0, 0.03, C.FreeThrowDistance / 2), PALETTE.Key, Enum.Material.SmoothPlastic, DECOR)
	local centerPaint = block(static, "CenterPaint", Vector3.new(0.06, C.CenterCircleRadius * 2, C.CenterCircleRadius * 2), origin * CFrame.new(0, 0.03, C.Length) * CFrame.Angles(0, 0, math.rad(90)), PALETTE.Key, Enum.Material.SmoothPlastic, DECOR)
	centerPaint.Shape = Enum.PartType.Cylinder

	courtLines(static, origin)
	buildHoop(static, origin)
	buildFence(static, origin)

	-- Floodlights at the four corners
	local lx = hw + C.Runoff + 3
	local target = origin:PointToWorldSpace(Vector3.new(0, 0, C.Length * 0.4))
	for _, spot in { Vector3.new(-lx, 0, -2), Vector3.new(lx, 0, -2), Vector3.new(-lx, 0, C.Length - 4), Vector3.new(lx, 0, C.Length - 4) } do
		lightPole(static, origin * CFrame.new(spot + Vector3.new(0, GROUND, 0)), target)
	end

	-- Benches outside the sidelines
	for _, x in { -(hw + C.Runoff + 3.5), hw + C.Runoff + 3.5 } do
		local facing = if x < 0 then math.rad(-90) else math.rad(90)
		bench(static, origin * CFrame.new(x, GROUND, C.Length * 0.45) * CFrame.Angles(0, facing, 0))
	end

	-- Queue pads in front of the half-court line
	local padZ = C.Length + C.Runoff + Config.Queue.PadDistance
	local gap = Config.Queue.PadGap / 2 + Config.Queue.PadSize / 2
	local homePad, homeLabel = buildPad(static, origin, "Home", Vector3.new(-gap, 0, padZ), Config.UI.Home)
	local awayPad, awayLabel = buildPad(static, origin, "Away", Vector3.new(gap, 0, padZ), Config.UI.Away)

	-- Court status sign over the entrance
	local signZ = C.Length + C.Runoff + 1
	for _, x in { -9, 9 } do
		block(static, "SignPost", Vector3.new(0.8, 13, 0.8), origin * CFrame.new(x, GROUND + 6.5, signZ), PALETTE.Metal, Enum.Material.Metal)
	end
	local signCF = CFrame.lookAt(origin:PointToWorldSpace(Vector3.new(0, 11.5, signZ)), origin:PointToWorldSpace(Vector3.new(0, 11.5, signZ + 10)))
	local sign = block(static, "StatusSign", Vector3.new(18, 4, 0.5), signCF, Config.UI.Panel, Enum.Material.SmoothPlastic)
	local signLabel = surfaceText(sign, Enum.NormalId.Front, def.DisplayName, Config.UI.Text, Config.UI.FontHeavy)
	surfaceText(sign, Enum.NormalId.Back, def.DisplayName, Config.UI.Accent, Config.UI.FontHeavy)

	local function face(localPos: Vector3, lookLocal: Vector3): CFrame
		local p = origin:PointToWorldSpace(localPos)
		local l = origin:PointToWorldSpace(lookLocal)
		return CFrame.lookAt(p, Vector3.new(l.X, p.Y, l.Z))
	end
	local returnZ = padZ + 7
	return {
		Id = def.Id,
		DisplayName = def.DisplayName,
		Model = model,
		Origin = origin,
		RimCenter = BasketballMath.RimCenter(origin),
		Pads = { Home = homePad, Away = awayPad },
		PadLabels = { Home = homeLabel, Away = awayLabel },
		SignLabel = signLabel,
		RackPosition = origin:PointToWorldSpace(Vector3.new(0, Config.Ball.Radius + 0.3, C.FreeThrowDistance)),
		ReturnSpots = {
			Home = face(Vector3.new(-gap - 3, 3.2, returnZ), Vector3.new(0, 0, 0)),
			Away = face(Vector3.new(gap + 3, 3.2, returnZ), Vector3.new(0, 0, 0)),
		},
	}
end

--------------------------------------------------------------------------------

function CourtBuilder.Build(): { CourtHandle }
	for _, name in { "Baseplate", "SpawnLocation" } do
		if workspace:FindFirstChild(name) then
			warn(("[CourtBuilder] Found a template '%s' in Workspace. Delete it in Studio (see PASTE_GUIDE step 2) so it does not overlap the park."):format(name))
		end
	end

	setupLighting()

	local existingPark = workspace:FindFirstChild("Park")
	if existingPark then
		existingPark:Destroy() -- only ever our own generated folder
	end
	local existingCourts = workspace:FindFirstChild("Courts")
	if existingCourts then
		existingCourts:Destroy()
	end

	local park = make("Folder", { Name = "Park" }, workspace) :: Folder
	local courtsFolder = make("Folder", { Name = "Courts" }, workspace) :: Folder

	local firstDef = Config.Courts[1]
	buildPark(park, BasketballMath.CourtOrigin(firstDef.Position, firstDef.Yaw))

	local courts = {}
	for _, def in Config.Courts do
		table.insert(courts, buildCourt(courtsFolder, def))
	end
	return courts
end

return CourtBuilder
