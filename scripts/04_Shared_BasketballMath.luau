--!strict
-- BasketballMath (ModuleScript) — ReplicatedStorage > Shared > BasketballMath
-- Pure functions: court geometry, shot zones, release timing and ball arcs.
-- No side effects, so the server can trust it and the client can preview with it.

local Config = require(script.Parent:WaitForChild("Config"))

local BasketballMath = {}
BasketballMath.ScriptFile = "04_Shared_BasketballMath" -- Main/ClientMain compare this to spot another file's code pasted here

local Court = Config.Court

-- Build the court origin CFrame (centre of the baseline, at floor-top height).
function BasketballMath.CourtOrigin(position: Vector3, yawDegrees: number): CFrame
	return CFrame.new(position + Vector3.new(0, Court.FloorTop, 0)) * CFrame.Angles(0, math.rad(yawDegrees), 0)
end

function BasketballMath.RimCenter(origin: CFrame): Vector3
	return origin:PointToWorldSpace(Vector3.new(0, Court.RimHeight, Court.RimDistance))
end

function BasketballMath.ToLocal(origin: CFrame, worldPosition: Vector3): Vector3
	return origin:PointToObjectSpace(worldPosition)
end

function BasketballMath.ToWorld(origin: CFrame, localPosition: Vector3): Vector3
	return origin:PointToWorldSpace(localPosition)
end

-- Flat (XZ) distance from a world position to the rim centre.
function BasketballMath.DistanceToRim(origin: CFrame, worldPosition: Vector3): number
	local p = origin:PointToObjectSpace(worldPosition)
	local dx = p.X
	local dz = p.Z - Court.RimDistance
	return math.sqrt(dx * dx + dz * dz)
end

-- True if the flat position is inside the playing area (lines are out).
-- `margin` grows the area (positive) or shrinks it (negative).
function BasketballMath.IsInBounds(origin: CFrame, worldPosition: Vector3, margin: number?): boolean
	local m = margin or 0
	local p = origin:PointToObjectSpace(worldPosition)
	return math.abs(p.X) < Court.Width / 2 + m and p.Z > -m and p.Z < Court.Length + m
end

-- Is a floor position behind the three-point line?
function BasketballMath.IsThreePointer(origin: CFrame, worldPosition: Vector3): boolean
	local p = origin:PointToObjectSpace(worldPosition)
	local dz = p.Z - Court.RimDistance
	local cornerBreakZ = Court.RimDistance
		+ math.sqrt(math.max(Court.ThreePointRadius ^ 2 - Court.CornerThreeX ^ 2, 0))
	if p.Z <= cornerBreakZ then
		-- Corner section: straight lines
		return math.abs(p.X) >= Court.CornerThreeX
	end
	return math.sqrt(p.X * p.X + dz * dz) >= Court.ThreePointRadius
end

function BasketballMath.ShotPoints(origin: CFrame, worldPosition: Vector3): number
	if BasketballMath.IsThreePointer(origin, worldPosition) then
		return Config.Scoring.OutsideArc
	end
	return Config.Scoring.InsideArc
end

export type ReleaseQuality = "Perfect" | "Good" | "Early" | "Late"

-- Classify a meter fill fraction (0..MaxHoldFraction).
function BasketballMath.ClassifyRelease(fraction: number): (ReleaseQuality, number)
	local shot = Config.Shot
	local delta = fraction - shot.IdealFraction
	local magnitude = math.abs(delta)
	if magnitude <= shot.PerfectWindow then
		return "Perfect", delta
	elseif magnitude <= shot.GoodWindow then
		return "Good", delta
	elseif delta < 0 then
		return "Early", delta
	end
	return "Late", delta
end

function BasketballMath.ArcHeight(distance: number): number
	return Config.Shot.ArcBase + Config.Shot.ArcPerStud * distance
end

-- Velocity that carries a projectile under `gravity` (positive number, pulling
-- down) from `from` to `to`, peaking at world height `apexY`.
-- Returns the launch velocity and the flight time.
function BasketballMath.SolveArc(from: Vector3, to: Vector3, apexY: number, gravity: number): (Vector3, number)
	local apex = math.max(apexY, from.Y + 0.5, to.Y + 0.5)
	local rise = apex - from.Y
	local fall = apex - to.Y
	local vy = math.sqrt(2 * gravity * rise)
	local tUp = vy / gravity
	local tDown = math.sqrt(2 * fall / gravity)
	local flightTime = tUp + tDown
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local horizontal = flat / flightTime
	return Vector3.new(horizontal.X, vy, horizontal.Z), flightTime
end

return BasketballMath
