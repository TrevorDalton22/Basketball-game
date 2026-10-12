--!strict
-- Config (ModuleScript) — ReplicatedStorage > Shared > Config
-- Every tunable gameplay value lives here. Server and client both read it,
-- but only the server's copy is ever trusted for gameplay decisions.

local Config = {}

-- Court geometry, in studs. Each court is a half court: the local origin is the
-- centre of the baseline at floor height, +Z points from the baseline toward
-- the half-court line.
Config.Court = {
	Width = 50, -- sideline to sideline
	Length = 47, -- baseline to half-court line
	FloorThickness = 1,
	FloorTop = 0.25, -- court surface sits slightly above the park ground (y = 0)
	Runoff = 6, -- painted out-of-bounds border around the playing area

	RimHeight = 10,
	RimRadius = 1.25, -- inner radius of the ring
	RimTube = 0.18, -- thickness of the ring
	RimDistance = 5.7, -- baseline to rim centre
	BackboardZ = 4, -- baseline to backboard front face
	BackboardSize = Vector2.new(7.2, 4.2),
	BackboardBottom = 9.5, -- height of the backboard's bottom edge

	ThreePointRadius = 22, -- measured from the rim centre, on the floor
	CornerThreeX = 21, -- straight corner-three lines sit at x = ±21
	KeyWidth = 16,
	FreeThrowDistance = 19, -- baseline to free-throw line
	FreeThrowCircleRadius = 6,
	RestrictedRadius = 4,
	CenterCircleRadius = 6,
	LineWidth = 0.35,

	-- Where players stand when a possession is checked (court-local x, z)
	OffenseSpot = Vector3.new(0, 0, 31),
	DefenseSpot = Vector3.new(0, 0, 24),
}

-- Courts that exist in the park. Phase 3 has one; add entries to add courts.
Config.Courts = {
	{ Id = "Court1", DisplayName = "COURT 1", Position = Vector3.new(0, 0, 0), Yaw = 0 },
}

Config.Lobby = {
	-- Spawn point relative to the first court's origin (in front of the half-court line)
	SpawnOffset = Vector3.new(0, 0, 78),
}

Config.Ball = {
	Radius = 0.65,
	Gravity = 80, -- the ball uses lower gravity than characters for a nicer arc
	Density = 0.6,
	Friction = 0.35,
	Elasticity = 0.62,
	ElasticityWeight = 3, -- how strongly the ball's bounciness wins over the surface it hits
	Color = Color3.fromRGB(232, 106, 23),
	SeamColor = Color3.fromRGB(30, 18, 10),

	-- Where the ball sits relative to the HumanoidRootPart while held
	HoldOffset = CFrame.new(1.05, -0.6, -1.35),
	-- Cosmetic only (client): ball raised for the shot
	ShootPoseOffset = CFrame.new(0.35, 2.3, -0.7),
	-- Cosmetic only (client): dribble bounce while moving
	DribbleFloorOffset = -2.3, -- relative to HRP, roughly the floor
	DribbleRate = 2.4, -- bounces per second at full run

	PickupHorizontal = 2.8, -- studs from HRP (flat distance)
	PickupBelow = 3.4, -- how far below the HRP a ball can be grabbed
	PickupAbove = 4.5, -- how far above the HRP (rebounds while jumping)
	ShooterRegrabDelay = 0.45, -- shooter cannot instantly re-grab their own release

	LooseTimeout = 12, -- untouched loose ball in a match gets reset
	PracticeIdleReset = 25, -- untouched practice ball returns to the rack
	PracticeHoldLimit = 15, -- nobody may hog the practice ball longer than this
	PracticeHogCooldown = 3, -- after hitting the limit, that player waits this long to grab it again
	KillHeight = -30, -- ball below this world height is reset
	FlightTimeout = 5, -- a shot that never resolves becomes a loose ball
	ScoredSettleTime = 0.7, -- practice: ball becomes grabbable again after a make
}

Config.Shot = {
	-- Timing meter: hold to fill, release on the green zone.
	FillTime = 0.6, -- seconds for the meter to go from 0 to 1
	IdealFraction = 0.82, -- centre of the green (perfect) zone
	PerfectWindow = 0.05, -- ± around the ideal
	GoodWindow = 0.13, -- ± around the ideal
	MaxHoldFraction = 1.15, -- the shot auto-releases (late) past this
	AirballFraction = 0.4, -- releasing below this is an airball

	-- The server measures the hold itself. The client's (more precise) value may
	-- only nudge that measurement by this much, to absorb normal network jitter.
	-- Keep it below the perfect half-window (PerfectWindow * FillTime = 0.03 s).
	ClientTimeTolerance = 0.025,
	MinShotInterval = 0.35, -- rate limit between shot starts
	ReleaseHeight = 2.4, -- launch point above the HRP
	ReleaseForward = 0.9,

	ArcBase = 4.5, -- apex height above the rim for a point-blank shot
	ArcPerStud = 0.16, -- extra apex height per stud of distance
	BackspinSpeed = 14,

	MakeChance = {
		Perfect = 0.97,
		Good = 0.5,
		Bad = 0.05, -- early / late
	},
	CloseRange = 9, -- inside this distance good releases get a bonus
	CloseBonus = 0.2,
	DeepRange = 30, -- past this, make chance falls off
	MaxRange = 46, -- at this distance the falloff reaches its floor
	DeepRangeFloor = 0.15, -- multiplier at MaxRange and beyond

	ContestRadius = 6, -- defenders closer than this reduce the make chance
	ContestMaxPenalty = 0.5, -- multiplier reduction for a defender right in your face
}

Config.Scoring = {
	InsideArc = 2,
	OutsideArc = 3,
}

Config.Match = {
	TargetScore = 15, -- first to this wins
	Duration = 240, -- game clock in seconds (only runs while the ball is live)
	CountdownTime = 3,
	DeadBallTime = 1.6, -- pause after a score or turnover before the check
	CheckTime = 1.2, -- players frozen at their spots before play resumes
	GameOverTime = 6, -- results screen before players return to the lobby
	MakeItTakeIt = false, -- false: the scored-on player gets the ball
	OutOfBounds = true,
	ShotClock = 20, -- one player may hold possession this long before it's a turnover
	OvertimeLimit = 120, -- overtime with no basket ends as a draw after this
	RespawnWait = 15, -- a participant who died must be back within this, or forfeits
	MaxResets = 3, -- resetting more often than this in one match forfeits it
}

Config.Players = {
	RespawnTime = 2, -- seconds (Roblox default is 5)
}

Config.AntiCheat = {
	-- Horizontal speed (studs/s) above which a player is treated as teleporting.
	-- Normal running is Movement.WalkSpeed (18); this leaves room for lag and knockback.
	MaxFlatSpeed = 45,
	SampleInterval = 0.25,
	PenaltyTime = 1.5, -- after a suspicious move: no pickups or shots for this long
}

Config.Queue = {
	PadSize = 6,
	PadGap = 8, -- distance between the two pads
	PadDistance = 7, -- distance in front of the half-court line
	StartDelay = 2, -- both pads filled → match starts after this unless someone steps off
	PollInterval = 0.2,
	ReclaimCooldown = 2, -- after pressing Leave, the pad ignores you for this long
}

Config.Movement = {
	WalkSpeed = 18,
	JumpHeight = 7.2,
	ShootingWalkSpeed = 5, -- cosmetic slow-down while holding a shot (client)
}

-- Collision groups (registered by CharacterService on the server)
Config.Collision = {
	Players = "Players",
	-- Match participants: bump into each other, but not into bystanders
	InMatch = "InMatch",
	Ball = "Ball",
	-- A shot the server already decided is a make flies in this group, which
	-- ignores the hoop (rim, backboard, supports), so physics can never turn a
	-- decided make into a miss.
	BallMake = "BallMake",
	Hoop = "Hoop",
}

Config.Remote = {
	-- Server-side per-player rate limit for every client → server remote
	MaxEventsPerSecond = 12,
}

Config.UI = {
	Font = Enum.Font.GothamBold,
	FontHeavy = Enum.Font.GothamBlack,
	FontBody = Enum.Font.GothamMedium,
	Panel = Color3.fromRGB(16, 20, 32),
	PanelLight = Color3.fromRGB(30, 36, 54),
	Text = Color3.fromRGB(245, 247, 252),
	TextDim = Color3.fromRGB(160, 168, 190),
	Accent = Color3.fromRGB(255, 140, 40),
	Home = Color3.fromRGB(64, 150, 255),
	Away = Color3.fromRGB(255, 78, 96),
	Perfect = Color3.fromRGB(70, 230, 120),
	Good = Color3.fromRGB(255, 214, 70),
	Bad = Color3.fromRGB(255, 80, 80),
}

return Config
