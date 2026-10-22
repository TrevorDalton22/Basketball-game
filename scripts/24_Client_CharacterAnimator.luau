--!strict
-- CharacterAnimator (ModuleScript) — StarterPlayer > StarterPlayerScripts > ClientMain > CharacterAnimator
-- Code-driven body animation, layered on top of Roblox's own walk, run and jump
-- animations. The arms follow the ball (dribble, crossover, shot set and
-- follow-through, layup, dunk and rim hang); defenders reach, contest and get
-- into a stance; players react (ankle breaks, a fist pump after a basket,
-- celebrating or slumping at the end). Each client poses every nearby
-- character itself from what the server already replicates (ball and court
-- attributes, published moves), so everyone sees the same thing. Works with
-- R15 and R6 avatars. Purely cosmetic: nothing here affects gameplay.
--
-- How it works: each frame, after Roblox's Animator has posed a joint, we read
-- that pose (the "base"), work out where the hands should be, solve the arm
-- joints to put them there (inverse kinematics) and blend the result over the
-- base by a weight that eases in and out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent
local MatchClient = require(Client:WaitForChild("MatchClient"))
local ShootController = require(Client:WaitForChild("ShootController"))
local MovesController = require(Client:WaitForChild("MovesController"))
local BallVisuals = require(Client:WaitForChild("BallVisuals"))

local CharacterAnimator = {}
CharacterAnimator.ScriptVersion = 2 -- ClientMain compares this to spot an old copy; bump when this file changes
CharacterAnimator.ScriptFile = "24_Client_CharacterAnimator" -- and this to spot another file's code pasted here

local ANIM = Config.Animation
local BALL = Config.Ball
local DEFENSE = Config.Defense
local MOVE_ATTRIBUTE = "StreetHoopsMove" -- set by the server's MovesService: "Reach:12", "Ankles:13"
local EMOTE_ATTRIBUTE = "StreetHoopsEmote" -- set by the server's CosmeticsService: "Flex:14"
local localPlayer = Players.LocalPlayer

-- Root space: the HumanoidRootPart's frame. +X right, +Y up, -Z forward.

--------------------------------------------------------------------------------
-- Rigs
--------------------------------------------------------------------------------

-- A body joint: a classic Motor6D, or the AnimationConstraint that R15 avatars
-- get with Roblox's Avatar Joint Upgrade. Both pose their child part as
-- Part0 * C0 * Transform * C1:Inverse(); a constraint's C0/C1 are its attachments.
type Joint = { Motor: Motor6D?, Constraint: AnimationConstraint? }

local function jointC0(joint: Joint): CFrame
	local m = joint.Motor
	if m then
		return m.C0
	end
	local attachment = (joint.Constraint :: AnimationConstraint).Attachment0
	return if attachment then attachment.CFrame else CFrame.identity
end

local function jointC1(joint: Joint): CFrame
	local m = joint.Motor
	if m then
		return m.C1
	end
	local attachment = (joint.Constraint :: AnimationConstraint).Attachment1
	return if attachment then attachment.CFrame else CFrame.identity
end

local function getTransform(joint: Joint): CFrame
	local m = joint.Motor
	return if m then m.Transform else (joint.Constraint :: AnimationConstraint).Transform
end

local function setTransform(joint: Joint, value: CFrame)
	local m = joint.Motor
	if m then
		m.Transform = value
	else
		(joint.Constraint :: AnimationConstraint).Transform = value
	end
end

-- The two parts a joint connects
local function jointParts(instance: Instance): (BasePart?, BasePart?)
	local part0: Instance?, part1: Instance? = nil, nil
	if instance:IsA("Motor6D") then
		part0, part1 = instance.Part0, instance.Part1
	elseif instance:IsA("AnimationConstraint") then
		local a0, a1 = instance.Attachment0, instance.Attachment1
		part0, part1 = if a0 then a0.Parent else nil, if a1 then a1.Parent else nil
	end
	if part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") then
		return part0, part1
	end
	return nil, nil
end

local function jointInstance(joint: Joint): Instance
	local m = joint.Motor
	if m then
		return m
	end
	return joint.Constraint :: AnimationConstraint
end

local function jointAlive(joint: Joint, character: Model): boolean
	local instance = jointInstance(joint)
	if not instance:IsDescendantOf(character) then
		return false
	end
	local part0, part1 = jointParts(instance)
	return part0 ~= nil and part1 ~= nil
end

type Arm = {
	Side: number, -- +1 right, -1 left
	Shoulder: Joint,
	Elbow: Joint?, -- R15 only (an R6 arm is one piece)
	Wrist: Joint?,
	Hand: BasePart, -- R15 hand, or the whole R6 arm
}
type Leg = { Hip: Joint, Knee: Joint? }
type Rig = {
	Character: Model,
	R6: boolean,
	RootJoint: Joint, -- root → LowerTorso (R15) or Torso (R6)
	Waist: Joint?, -- R15: LowerTorso → UpperTorso
	Neck: Joint?,
	Right: Arm,
	Left: Arm,
	RightLeg: Leg?,
	LeftLeg: Leg?,
	Joints: { Joint },
}

-- Joints are found by the parts they connect (names and parents vary between
-- joint types), e.g. the one moving "RightUpperArm" from "UpperTorso"
local function buildRig(character: Model, humanoid: Humanoid): Rig?
	type Found = { Joint: Joint, Parent: string, Part: BasePart }
	local byPart: { [string]: Found } = {}
	for _, instance in character:GetDescendants() do
		local part0, part1 = jointParts(instance)
		if part0 and part1 and part1:IsDescendantOf(character) then
			local joint: Joint = if instance:IsA("Motor6D") then { Motor = instance } else { Constraint = instance :: AnimationConstraint }
			byPart[part1.Name] = { Joint = joint, Parent = part0.Name, Part = part1 }
		end
	end
	local joints: { Joint } = {}
	local function find(partName: string, parentName: string): (Joint?, BasePart?)
		local found = byPart[partName]
		if found and found.Parent == parentName then
			table.insert(joints, found.Joint)
			return found.Joint, found.Part
		end
		return nil, nil
	end

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local rootJoint = find("Torso", "HumanoidRootPart")
		local right, rightArm = find("Right Arm", "Torso")
		local left, leftArm = find("Left Arm", "Torso")
		if not rootJoint or not right or not left or not rightArm or not leftArm then
			return nil
		end
		local rightHip = (find("Right Leg", "Torso"))
		local leftHip = (find("Left Leg", "Torso"))
		return {
			Character = character,
			R6 = true,
			RootJoint = rootJoint,
			Waist = nil,
			Neck = (find("Head", "Torso")),
			Right = { Side = 1, Shoulder = right, Hand = rightArm },
			Left = { Side = -1, Shoulder = left, Hand = leftArm },
			RightLeg = if rightHip then { Hip = rightHip } else nil,
			LeftLeg = if leftHip then { Hip = leftHip } else nil,
			Joints = joints,
		}
	end
	local rootJoint = find("LowerTorso", "HumanoidRootPart")
	local waist = find("UpperTorso", "LowerTorso")
	local function arm(side: number, prefix: string): Arm?
		local shoulder = find(prefix .. "UpperArm", "UpperTorso")
		local elbow = find(prefix .. "LowerArm", prefix .. "UpperArm")
		local wrist, hand = find(prefix .. "Hand", prefix .. "LowerArm")
		if not shoulder or not elbow or not wrist or not hand then
			return nil
		end
		return { Side = side, Shoulder = shoulder, Elbow = elbow, Wrist = wrist, Hand = hand }
	end
	local right, left = arm(1, "Right"), arm(-1, "Left")
	if not rootJoint or not waist or not right or not left then
		return nil
	end
	local function leg(prefix: string): Leg?
		local hip = find(prefix .. "UpperLeg", "LowerTorso")
		local knee = find(prefix .. "LowerLeg", prefix .. "UpperLeg")
		return if hip then { Hip = hip, Knee = knee } else nil
	end
	return {
		Character = character,
		R6 = false,
		RootJoint = rootJoint,
		Waist = waist,
		Neck = (find("Head", "UpperTorso")),
		Right = right,
		Left = left,
		RightLeg = leg("Right"),
		LeftLeg = leg("Left"),
		Joints = joints,
	}
end

-- False once any joint was removed or rebuilt (respawn, appearance load, rescale)
local function rigIntact(rig: Rig): boolean
	for _, joint in rig.Joints do
		if not jointAlive(joint, rig.Character) then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- CFrame helpers
--------------------------------------------------------------------------------

local function rotation(cf: CFrame): CFrame
	return cf - cf.Position
end

-- Shortest rotation taking direction a onto direction b (both unit)
local function between(a: Vector3, b: Vector3): CFrame
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 0.999999 then
		return CFrame.identity
	end
	if dot < -0.999999 then
		-- Opposite: turn about any axis square to a (prefer the side-to-side one)
		local axis = a:Cross(Vector3.xAxis)
		if axis.Magnitude < 1e-3 then
			axis = a:Cross(Vector3.zAxis)
		end
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(a:Cross(b).Unit, math.acos(dot))
end

-- A rotation that turns `localAlong` onto `worldAlong` and, around that, the
-- side direction `localSide` onto `worldSide` (both squared up first)
local function basis(along: Vector3, side: Vector3): CFrame
	local y = along.Unit
	local x = side - y * side:Dot(y)
	if x.Magnitude < 1e-4 then
		x = y:Cross(Vector3.zAxis)
		if x.Magnitude < 1e-4 then
			x = y:Cross(Vector3.xAxis)
		end
	end
	x = x.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end
local function aligned(localAlong: Vector3, localSide: Vector3, worldAlong: Vector3, worldSide: Vector3): CFrame
	return basis(worldAlong, worldSide) * basis(localAlong, localSide):Inverse()
end

-- A rotation given in a joint's Part0 frame, as a Transform for that joint
local function inJoint(joint: Joint, rotationInPart0: CFrame): CFrame
	local c0 = rotation(jointC0(joint))
	return c0:Inverse() * rotationInPart0 * c0
end

-- Root-space lean: pitch > 0 tips forward, roll > 0 tips to the right
local function leanRotation(pitch: number, roll: number): CFrame
	return CFrame.Angles(-pitch, 0, -roll)
end

local function smooth(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function ease(w: number): number
	return w * w * (3 - 2 * w)
end

--------------------------------------------------------------------------------
-- Per-character state
--------------------------------------------------------------------------------

type ArmGoal = {
	Target: Vector3, -- where the hand should be (root space)
	Pole: Vector3, -- which way the elbow points (root space)
	Flex: number, -- wrist bend, radians: > 0 bends the hand the way the elbow folds, < 0 back
	Layer: string,
	BlendIn: number?,
}
type Limb = {
	Weight: number,
	Target: Vector3,
	Pole: Vector3,
	Flex: number,
	Layer: string,
	SwitchedAt: number,
	Shoulder: Vector3, -- where we put the shoulder this frame (root space)
	Reachable: boolean, -- the target was within the arm's reach this frame
}
type Written = { Last: CFrame, Base: CFrame }
type Track = {
	Player: Player,
	Rig: Rig?,
	Character: Model?,
	Limbs: { [number]: Limb }, -- keyed by side (+1 right, -1 left)
	Knees: { [number]: number }, -- knee-raise weight per side
	Pitch: number,
	Roll: number,
	LookWeight: number,
	Look: Vector3,
	Move: string, -- latest one-off move: "Reach", "Ankles"
	MoveAt: number,
	MoveAttribute: any,
	Emote: string, -- the emote playing (or ""), and when it started
	EmoteAt: number,
	EmoteAttribute: any,
	Broken: Model?, -- this character's rig made the solver fail: leave it alone
	Release: string, -- last shot that left this player's hands: "Jumper", "Layup", "Dunk"
	ReleaseAt: number,
	ReleaseSide: number,
	ReleaseRim: Vector3?,
	ScoredAt: number,
	AirborneUntil: number,
	LastPosition: Vector3?,
	Velocity: Vector3, -- measured from how the root moved (see measureVelocity)
	Written: { [Joint]: Written },
}

local tracks: { [Player]: Track } = {}
local localReachAt = -math.huge

local function newLimb(side: number): Limb
	return {
		Weight = 0,
		Target = Vector3.new(side, -1, 0),
		Pole = Vector3.new(side, -1, 1),
		Flex = 0,
		Layer = "",
		SwitchedAt = 0,
		Shoulder = Vector3.zero,
		Reachable = false,
	}
end

local function getTrack(player: Player): Track
	local track = tracks[player]
	if not track then
		track = {
			Player = player,
			Rig = nil,
			Character = nil,
			Limbs = { [1] = newLimb(1), [-1] = newLimb(-1) },
			Knees = { [1] = 0, [-1] = 0 },
			Pitch = 0,
			Roll = 0,
			LookWeight = 0,
			Look = Vector3.new(0, 0, -1),
			Move = "",
			MoveAt = -math.huge,
			MoveAttribute = player:GetAttribute(MOVE_ATTRIBUTE), -- don't replay a move from before we saw them
			Emote = "",
			EmoteAt = -math.huge,
			EmoteAttribute = player:GetAttribute(EMOTE_ATTRIBUTE),
			Release = "",
			ReleaseAt = -math.huge,
			ReleaseSide = 1,
			ReleaseRim = nil,
			ScoredAt = -math.huge,
			AirborneUntil = 0,
			LastPosition = nil,
			Velocity = Vector3.zero,
			Broken = nil,
			Written = {},
		}
		tracks[player] = track
	end
	return track
end

-- The joint's pose without us: what the Animator last wrote. If it hasn't
-- rewritten the joint since our write (joint not animated, or skipped this
-- frame), our own value is still there, so use the last base we saw instead.
local function baseOf(track: Track, joint: Joint): CFrame
	local current = getTransform(joint)
	local record = track.Written[joint]
	if record then
		if current == record.Last then
			return record.Base
		end
		record.Base = current
	end
	return current
end

local function write(track: Track, joint: Joint, base: CFrame, value: CFrame)
	setTransform(joint, value)
	local stored = getTransform(joint) -- read back: stored precision can differ
	local record = track.Written[joint]
	if record then
		record.Last, record.Base = stored, base
	else
		track.Written[joint] = { Last = stored, Base = base }
	end
end

-- Hand a joint back to the Animator
local function restore(track: Track, joint: Joint)
	local record = track.Written[joint]
	if record then
		if jointInstance(joint).Parent and getTransform(joint) == record.Last then
			setTransform(joint, record.Base)
		end
		track.Written[joint] = nil
	end
end

local function restoreAll(track: Track)
	for joint in track.Written do
		restore(track, joint)
	end
	table.clear(track.Written)
	track.Limbs[1], track.Limbs[-1] = newLimb(1), newLimb(-1)
	track.Knees[1], track.Knees[-1] = 0, 0
	track.Pitch, track.Roll, track.LookWeight = 0, 0, 0
	track.LastPosition, track.Velocity = nil, Vector3.zero
end

--------------------------------------------------------------------------------
-- Forward kinematics and arm IK (all in root space)
--------------------------------------------------------------------------------

-- The part the shoulders and neck hang from (UpperTorso / Torso), given the lean
local function chestFrame(track: Track, rig: Rig, lean: CFrame?): (CFrame, CFrame, CFrame?)
	local rootJoint = rig.RootJoint
	local rootBase = baseOf(track, rootJoint)
	if rig.R6 then
		local rootT = if lean then inJoint(rootJoint, lean) * rootBase else rootBase
		local torso = jointC0(rootJoint) * rootT * jointC1(rootJoint):Inverse()
		return torso, rootT, nil
	end
	local waist = rig.Waist :: Joint
	local lowerTorso = jointC0(rootJoint) * rootBase * jointC1(rootJoint):Inverse()
	local waistBase = baseOf(track, waist)
	local waistT = waistBase
	if lean then
		local lt = rotation(lowerTorso)
		waistT = inJoint(waist, lt:Inverse() * lean * lt) * waistBase
	end
	local upperTorso = lowerTorso * jointC0(waist) * waistT * jointC1(waist):Inverse()
	return upperTorso, rootBase, waistT
end

local function shoulderOf(chest: CFrame, arm: Arm): Vector3
	return (chest * jointC0(arm.Shoulder)).Position
end

-- The middle of the palm, in the hand's own space (R6: the end of the arm)
local function palmOf(arm: Arm): Vector3
	local grip = arm.Hand:FindFirstChild(if arm.Side > 0 then "RightGripAttachment" else "LeftGripAttachment")
	if grip and grip:IsA("Attachment") then
		return grip.Position
	end
	return Vector3.new(0, -arm.Hand.Size.Y * 0.5, 0)
end

local ELBOW_MAX = math.rad(150) -- an elbow folds this far at most (and never bends backwards)
-- Near full stretch a tiny change in distance swings the elbow a lot; ease into
-- straight over this last bit (studs) so a target crossing it doesn't snap the arm
local SOFT_REACH = 0.05

-- The elbow turns only about its own joint X axis. With the hand set by the
-- wrist bend, this works out how far the palm is from the shoulder pivot for
-- any elbow bend, and the bend that gives a wanted distance, exactly (law of
-- cosines around that axis; the shoulder pivot sits off the arm's centre line,
-- so the plain two-bone formula would twist the elbow sideways).
type Hinge = { Reach: number, Shortest: number, BendFor: (distance: number) -> number }
local function hingeOf(arm: Arm, palmInForearm: Vector3): Hinge
	local elbow = arm.Elbow :: Joint
	local elC0, elC1 = jointC0(elbow), jointC1(elbow)
	-- In the elbow joint's own frame: the palm before bending, and the shoulder
	local p = elC1:Inverse() * palmInForearm
	local q = elC0:Inverse() * jointC1(arm.Shoulder).Position
	-- |Rx(theta) p - q|^2 = k - 2 m cos(theta - phi)
	local a = q.Y * p.Y + q.Z * p.Z
	local b = q.Z * p.Y - q.Y * p.Z
	local m = math.sqrt(a * a + b * b)
	local phi = math.atan2(b, a)
	local k = p:Dot(p) + q:Dot(q) - 2 * q.X * p.X
	local function distanceAt(theta: number): number
		return math.sqrt(math.max(k - 2 * m * math.cos(theta - phi), 0))
	end
	-- Farthest reach is at phi + pi; the arm can't go past straight or fold past ELBOW_MAX
	local farthest = (phi + math.pi + math.pi) % (2 * math.pi) - math.pi
	local straightest = math.clamp(farthest, 0, ELBOW_MAX)
	local reach, shortest = distanceAt(straightest), distanceAt(ELBOW_MAX)
	return {
		Reach = reach,
		Shortest = shortest,
		BendFor = function(distance: number): number
			if m < 1e-6 then
				return straightest
			end
			local d = math.clamp(distance, shortest, reach)
			local c = math.clamp((k - d * d) / (2 * m), -1, 1)
			-- Past the farthest point the palm comes closer as the elbow folds
			return math.clamp(farthest + math.acos(-c), straightest, ELBOW_MAX)
		end,
	}
end

-- How far the palm reaches from the shoulder with the arm straight
local function reachOf(arm: Arm): number
	local shC1 = jointC1(arm.Shoulder)
	if arm.Elbow and arm.Wrist then
		local wrist = arm.Wrist :: Joint
		return hingeOf(arm, (jointC0(wrist) * jointC1(wrist):Inverse()) * palmOf(arm)).Reach
	end
	return (palmOf(arm) - shC1.Position).Magnitude
end

type ArmPose = { Shoulder: CFrame, Elbow: CFrame?, Wrist: CFrame? }

-- Joint Transforms that put the palm on `target` (or as close as the arm
-- reaches), with the elbow towards `pole`. Absolute values, so nothing builds
-- up from frame to frame.
local function solveArm(arm: Arm, chest: CFrame, target: Vector3, pole: Vector3, flex: number): ArmPose?
	local shoulder = arm.Shoulder
	local pivot = chest * jointC0(shoulder)
	local S = pivot.Position
	local shC1 = jointC1(shoulder)
	local toTarget = target - S
	local distance = toTarget.Magnitude
	if distance < 1e-3 or distance ~= distance then
		return nil
	end
	local direction = toTarget / distance

	if not arm.Elbow or not arm.Wrist then
		-- R6: one straight piece, so just point it at the target
		local bone = palmOf(arm) - shC1.Position
		if bone.Magnitude < 1e-3 then
			return nil
		end
		local upperRest = rotation(pivot * shC1:Inverse())
		local turned = between(upperRest:VectorToWorldSpace(bone.Unit), direction) * upperRest
		local part = CFrame.new(S) * turned * CFrame.new(-shC1.Position)
		return { Shoulder = rotation(pivot:Inverse() * part * shC1) }
	end

	local elbow, wrist = arm.Elbow :: Joint, arm.Wrist :: Joint
	local elC0, elC1 = jointC0(elbow), jointC1(elbow)
	-- Bend the wrist about the forearm's side-to-side axis (flex > 0: the way
	-- the elbow folds); then the palm's place in the forearm is fixed
	local wristT = inJoint(wrist, CFrame.Angles(flex, 0, 0))
	local palmInForearm = (jointC0(wrist) * wristT * jointC1(wrist):Inverse()) * palmOf(arm)
	-- Fold the elbow (a hinge about its own X axis) until shoulder-to-palm is
	-- the distance to the target...
	local elbowHinge = hingeOf(arm, palmInForearm)
	local wanted = distance
	local softStart = elbowHinge.Reach - SOFT_REACH
	if wanted > softStart then
		wanted = elbowHinge.Reach - SOFT_REACH * math.exp(-(wanted - softStart) / SOFT_REACH)
	end
	local theta = elbowHinge.BendFor(wanted)
	local elbowT = CFrame.Angles(theta, 0, 0)
	local palmInUpper = (elC0 * elbowT * elC1:Inverse()) * palmInForearm - shC1.Position
	if palmInUpper.Magnitude < 1e-3 then
		return nil
	end
	-- ...then turn the whole arm at the shoulder so the palm points at the
	-- target and the elbow sits towards the pole, square to its hinge
	local bend = pole - direction * pole:Dot(direction)
	if bend.Magnitude < 1e-3 then
		bend = direction:Cross(Vector3.xAxis)
		if bend.Magnitude < 1e-3 then
			bend = direction:Cross(Vector3.zAxis)
		end
	end
	local hinge = bend.Unit:Cross(direction)
	local upperRot = aligned(palmInUpper, rotation(elC0).XVector, direction, hinge)
	local upper = CFrame.new(S) * upperRot * CFrame.new(-shC1.Position)
	return {
		Shoulder = rotation(pivot:Inverse() * upper * shC1),
		Elbow = elbowT,
		Wrist = wristT,
	}
end

--------------------------------------------------------------------------------
-- What's going on in the world this frame
--------------------------------------------------------------------------------

type BallInfo = {
	Part: BasePart,
	Court: Model,
	State: string,
	Holder: number,
	Shooting: boolean,
	Kind: string, -- while shooting: "Jumper", "Layup" or "Dunk"
}
-- Holder/Kind/Side: the last player seen holding it, what they were shooting, and with which hand
type BallTrack = { State: string, Holder: number, HeldAt: number, Kind: string, Side: number }
local ballTracks: { [string]: BallTrack } = {} -- by court id (one ball per court)
type CourtTrack = { Home: number, Away: number }
local courtTracks: { [string]: CourtTrack } = {}

local heldBy: { [number]: BallInfo } = {}
local balls: { BallInfo } = {}

local function attrNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function attrString(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if typeof(value) == "string" then value else ""
end

local function playerById(id: number): Player?
	return if id ~= 0 then Players:GetPlayerByUserId(id) else nil
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Where a held ball sits in its holder's root space (BallVisuals moves it there)
local function heldBallOffset(ball: BasePart, root: BasePart): Vector3
	local weld = ball:FindFirstChild("HoldWeld")
	if weld and weld:IsA("Weld") and weld.Part0 == root then
		return (weld.C0 * weld.C1:Inverse()).Position
	end
	return root.CFrame:PointToObjectSpace(ball.Position)
end

local function scanBalls(now: number)
	table.clear(heldBy)
	table.clear(balls)
	local seen: { [string]: boolean } = {}
	local localKind = ShootController.GetLocalShot()
	for _, court in MatchClient.GetCourts() do
		local part = MatchClient.GetBall(court)
		if not part or court.Parent == nil then
			continue
		end
		local courtId = attrString(court, "CourtId")
		seen[courtId] = true
		local state = attrString(part, "State")
		local holder = attrNumber(part, "HolderUserId")
		local shooting = part:GetAttribute("Shooting") == true
		local finish = attrString(part, "Finish")
		local bt = ballTracks[courtId]
		if not bt then
			bt = { State = state, Holder = 0, HeldAt = -math.huge, Kind = "", Side = 1 }
			ballTracks[courtId] = bt
		end
		-- Our own shot shows straight away; the server's attributes follow
		if holder == localPlayer.UserId and localKind then
			shooting = true
			finish = if localKind == "Jumper" then "" else localKind
		end
		if state == "Held" and holder ~= 0 then
			if holder ~= bt.Holder then
				bt.Kind = ""
			end
			if shooting then
				if finish ~= "" then
					bt.Kind = finish
				elseif bt.Kind == "" then
					bt.Kind = "Jumper"
				end
			else
				bt.Kind = ""
			end
			bt.Holder, bt.HeldAt = holder, now
			-- Which hand it's in, for the follow-through after it leaves
			local holderRoot = rootOf(playerById(holder))
			if holderRoot then
				local offset = heldBallOffset(part, holderRoot)
				if math.abs(offset.X) > 0.15 then
					bt.Side = if offset.X > 0 then 1 else -1
				end
			end
		end
		-- Left the shooter's hands: start their follow-through. (The server
		-- clears the holder just before it launches the ball, so go by the
		-- last holder we saw.)
		if state == "InFlight" and bt.State ~= "InFlight" and bt.Holder ~= 0 and now - bt.HeldAt < 0.5 then
			local shooter = playerById(bt.Holder)
			if shooter then
				local track = getTrack(shooter)
				-- The server's final say (a stopped-short dunk becomes a layup), else what we saw
				local shotKind = attrString(part, "ShotKind")
				track.Release = if shotKind ~= "" then shotKind elseif bt.Kind ~= "" then bt.Kind else "Jumper"
				track.ReleaseAt = now
				track.ReleaseSide = bt.Side
				local rim = court:GetAttribute("RimCenter")
				track.ReleaseRim = if typeof(rim) == "Vector3" then rim else nil
			end
		end
		if state ~= "Held" then
			bt.Holder, bt.Kind = 0, ""
		end
		bt.State = state
		local info: BallInfo = { Part = part, Court = court, State = state, Holder = holder, Shooting = shooting, Kind = if shooting then bt.Kind else "" }
		table.insert(balls, info)
		if state == "Held" and holder ~= 0 then
			heldBy[holder] = info
		end
	end
	for courtId in ballTracks do
		if not seen[courtId] then
			ballTracks[courtId] = nil
		end
	end
end

local function scanCourts(now: number)
	for _, court in MatchClient.GetCourts() do
		local home, away = attrNumber(court, "HomeScore"), attrNumber(court, "AwayScore")
		local courtId = attrString(court, "CourtId")
		local ct = courtTracks[courtId]
		if ct then
			for _, side in { "Home", "Away" } do
				local score = if side == "Home" then home else away
				if score > (if side == "Home" then ct.Home else ct.Away) then
					local scorer = playerById(attrNumber(court, side .. "UserId"))
					if scorer then
						getTrack(scorer).ScoredAt = now
					end
				end
			end
		end
		courtTracks[courtId] = { Home = home, Away = away }
	end
end

-- The court this player is in a match on, and their opponent's user id
local function matchOf(player: Player): (Model?, number)
	local id = player.UserId
	for _, court in MatchClient.GetCourts() do
		if court:GetAttribute("HomeUserId") == id then
			return court, attrNumber(court, "AwayUserId")
		elseif court:GetAttribute("AwayUserId") == id then
			return court, attrNumber(court, "HomeUserId")
		end
	end
	return nil, 0
end

local function rimOf(court: Model?): Vector3?
	local rim = court and court:GetAttribute("RimCenter")
	return if typeof(rim) == "Vector3" then rim else nil
end

--------------------------------------------------------------------------------
-- Goals: what each part of the body should be doing this frame
--------------------------------------------------------------------------------

type Goals = {
	Arms: { [number]: ArmGoal? },
	Pitch: number,
	Roll: number,
	Knees: { [number]: boolean },
	Look: Vector3?, -- direction (root space) for the head, if any
}

local function armGoal(target: Vector3, pole: Vector3, flex: number, layer: string, blendIn: number?): ArmGoal
	return { Target = target, Pole = pole, Flex = flex, Layer = layer, BlendIn = blendIn }
end

-- Toward a point, but no farther than `length` (keeps an over-reach straight)
local function toward(from: Vector3, point: Vector3, length: number): Vector3
	local offset = point - from
	local distance = offset.Magnitude
	if distance < 1e-3 then
		return from + Vector3.new(0, -length, 0)
	end
	return from + offset / distance * math.min(distance, length)
end

-- Velocity from how the root actually moved since last frame. Roblox doesn't
-- send other players' velocity to this client, so their own value can be
-- missing or coarse; their position is always there.
local function measureVelocity(track: Track, root: BasePart, dt: number)
	local position = root.Position
	local last = track.LastPosition
	track.LastPosition = position
	if not last or dt <= 0 then
		return
	end
	local raw = (position - last) / dt
	if raw.Magnitude > 150 then
		return -- a teleport, not movement
	end
	track.Velocity = track.Velocity:Lerp(raw, smooth(25, dt))
end

-- Emotes (bought in the shop), as hand targets around the shoulders. t is the
-- time since it started.
local function emoteGoals(goals: Goals, name: string, t: number, rig: Rig, chest: CFrame, shoulders: { [number]: Vector3 }, reach: { [number]: number })
	local function arm(side: number, offset: Vector3, pole: Vector3, flex: number)
		goals.Arms[side] = armGoal(shoulders[side] + offset * reach[side], pole, flex, "Emote")
	end
	if name == "Wave" then
		arm(1, Vector3.new(0.35 + 0.15 * math.sin(t * 9), 0.85, -0.15), Vector3.new(1, -0.6, 0.3), 0)
		goals.Look = Vector3.new(0, 0.1, -1)
	elseif name == "Flex" then
		-- Upper arms out to the sides, fists up by the head
		local pulse = 0.04 * math.sin(t * 10)
		for side = -1, 1, 2 do
			arm(side, Vector3.new(side * 0.34, 0.56 + pulse, 0.02), Vector3.new(side, -1, 0), 0.6)
		end
		goals.Pitch = -0.06
	elseif name == "Shrug" then
		for side = -1, 1, 2 do
			arm(side, Vector3.new(side * 0.5, -0.5, -0.45), Vector3.new(side, -0.3, 0.6), -0.9)
		end
		goals.Roll = 0.06
		goals.Look = Vector3.new(0.3, 0.15, -1)
	elseif name == "Salute" then
		-- Fingertips to the forehead
		local head = chest.Position + Vector3.new(0, 1.3, 0)
		if rig.Neck then
			local neck = rig.Neck :: Joint
			head = (chest * jointC0(neck) * jointC1(neck):Inverse()).Position
		end
		goals.Arms[1] = armGoal(head + Vector3.new(0.3, 0.25, -0.5), Vector3.new(1, -0.2, 0), 0.3, "Emote")
		goals.Look = Vector3.new(0, 0.05, -1)
	elseif name == "RaiseRoof" then
		local pump = 0.15 * math.sin(t * 10)
		for side = -1, 1, 2 do
			arm(side, Vector3.new(side * 0.3, 0.55 + pump, -0.25), Vector3.new(side, -0.6, 0.2), -1)
		end
		goals.Look = Vector3.new(0, 0.4, -1)
	elseif name == "FingerWag" then
		arm(1, Vector3.new(-0.05 + 0.05 * math.sin(t * 14), 0.42, -0.35), Vector3.new(1, -1, 0.3), 0.5 * math.sin(t * 14))
		goals.Look = Vector3.new(0.35 * math.sin(t * 7), 0.05, -1)
	end
end

local function computeGoals(track: Track, rig: Rig, root: BasePart, chest: CFrame, dt: number, now: number): Goals
	local player = track.Player
	local goals: Goals = { Arms = {}, Pitch = 0, Roll = 0, Knees = {}, Look = nil }
	local rootCF = root.CFrame
	local shoulders = { [1] = shoulderOf(chest, rig.Right), [-1] = shoulderOf(chest, rig.Left) }
	local reach = { [1] = reachOf(rig.Right), [-1] = reachOf(rig.Left) }
	local velocity = track.Velocity
	local localVelocity = rootCF:VectorToObjectSpace(velocity)
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if math.abs(velocity.Y) > 8 then
		track.AirborneUntil = now + 0.2
	end
	local airborne = now < track.AirborneUntil
	local court, opponentId = matchOf(player)
	local courtState = if court then attrString(court, "State") else ""
	local held = heldBy[player.UserId]

	local function toLocal(world: Vector3): Vector3
		return rootCF:PointToObjectSpace(world)
	end
	local function lookAt(world: Vector3?)
		if world then
			goals.Look = toLocal(world) - (chest * CFrame.new(0, 1, 0)).Position
		end
	end

	-- 1. End of a match: the winner celebrates, the loser slumps
	if courtState == "GameOver" and court then
		local winner = attrNumber(court, "WinnerUserId")
		local t = now * 9
		if winner == player.UserId then
			for side = -1, 1, 2 do
				local s = shoulders[side]
				local pump = 0.85 + 0.3 * math.sin(t + (if side > 0 then 0 else math.pi))
				goals.Arms[side] = armGoal(s + Vector3.new(side * 0.35, pump, -0.25) * reach[side], Vector3.new(side, -0.2, 0.4), 0, "Celebrate")
			end
			goals.Pitch = -0.08
			goals.Look = Vector3.new(0, 0.6, -1)
			return goals
		elseif winner ~= 0 then
			-- Hands on knees
			for side = -1, 1, 2 do
				local knee = Vector3.new(side * 0.55, -1.7, -0.75)
				goals.Arms[side] = armGoal(knee + Vector3.new(0, 0.35, -0.25), Vector3.new(side, 0.2, 0.6), 0, "Slump")
			end
			goals.Pitch = if rig.R6 then 0.25 else 0.55
			goals.Look = Vector3.new(0, -0.8, -1)
			return goals
		end
	end

	-- 2. Ankles broken: arms flailing, wobbling backwards
	local sinceMove = now - track.MoveAt
	if track.Move == "Ankles" and sinceMove < DEFENSE.AnklesSlowTime then
		local fade = 1 - sinceMove / DEFENSE.AnklesSlowTime
		for side = -1, 1, 2 do
			local s = shoulders[side]
			local wave = math.sin(now * 13 + side)
			goals.Arms[side] = armGoal(s + Vector3.new(side * 1.5, 0.3 + 0.6 * wave, 0.4 + 0.3 * math.cos(now * 11)), Vector3.new(side, -0.5, 0.5), 0, "Ankles", 18)
		end
		goals.Pitch = -0.18 * fade
		goals.Roll = 0.28 * math.sin(now * 9) * fade
		return goals
	end

	-- 3. Just released a shot: follow-through, or hanging on the rim after a dunk
	local sinceRelease = now - track.ReleaseAt
	local releaseSide = track.ReleaseSide
	if track.Release == "Dunk" and sinceRelease < ANIM.RimHangTime and (airborne or sinceRelease < 0.25) and track.ReleaseRim then
		local rim = toLocal(track.ReleaseRim :: Vector3)
		local flat = Vector3.new(rim.X, 0, rim.Z)
		local forward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local across = Vector3.new(-forward.Z, 0, forward.X)
		local front = rim - forward * Config.Court.RimRadius + Vector3.new(0, 0.15, 0)
		for side = -1, 1, 2 do
			goals.Arms[side] = armGoal(toward(shoulders[side], front + across * (side * 0.6), reach[side] * 1.05), Vector3.new(side * 0.15, -1, 0.3), 0, "Hang", 22)
		end
		goals.Pitch = 0.1
		goals.Look = rim
		return goals
	end
	if (track.Release == "Jumper" or track.Release == "Layup") and sinceRelease < ANIM.FollowThroughTime then
		local s = shoulders[releaseSide]
		local up: Vector3
		if track.Release == "Layup" and track.ReleaseRim then
			local toRim = (toLocal(track.ReleaseRim :: Vector3) - s).Unit
			up = (toRim + Vector3.new(0, 0.8, 0)).Unit
		else
			up = Vector3.new(releaseSide * 0.05, 0.86, -0.5).Unit
		end
		goals.Arms[releaseSide] = armGoal(s + up * reach[releaseSide] * 1.05, Vector3.new(releaseSide * 0.3, -0.3, -1), if track.Release == "Jumper" then -1.2 else -0.5, "Follow", 30)
		if track.Release == "Jumper" then
			local o = shoulders[-releaseSide]
			goals.Arms[-releaseSide] = armGoal(o + Vector3.new(-releaseSide * 0.25, 0.6, -0.7) * reach[-releaseSide], Vector3.new(-releaseSide, -0.5, 0), 0, "Follow")
		else
			goals.Knees[-releaseSide] = airborne
		end
		goals.Pitch = -0.04
		return goals
	end

	-- 3b. An emote (never with the ball: picking it up ends the emote)
	if held then
		track.Emote = ""
	elseif track.Emote ~= "" and now - track.EmoteAt < Config.Cosmetics.EmoteTime then
		emoteGoals(goals, track.Emote, now - track.EmoteAt, rig, chest, shoulders, reach)
		return goals
	end

	-- 4. Holding the ball
	if held then
		local ball = heldBallOffset(held.Part, root)
		local radius = BALL.Radius
		local rim = rimOf(held.Court)
		if held.Shooting and held.Kind == "Dunk" then
			for side = -1, 1, 2 do
				goals.Arms[side] = armGoal(ball + Vector3.new(side * radius * 0.95, 0, 0.1), Vector3.new(side, -0.4, 0.3), 0, "DunkSet", 16)
			end
			goals.Pitch = -0.1
			lookAt(rim)
			return goals
		elseif held.Shooting and held.Kind == "Layup" then
			local side = if ball.X >= 0 then 1 else -1
			goals.Arms[side] = armGoal(ball - Vector3.new(0, radius, -0.05), Vector3.new(side * 0.6, -0.6, -0.3), 0.3, "LayupSet", 16)
			local o = shoulders[-side]
			goals.Arms[-side] = armGoal(o + Vector3.new(-side * 0.35, 0.45, -0.55) * reach[-side], Vector3.new(-side, -0.5, 0.2), 0, "LayupSet")
			goals.Knees[-side] = true
			lookAt(rim)
			return goals
		elseif held.Shooting then
			-- Jump shot set: shooting hand under and behind the ball, guide hand on its side
			local side = if ball.X >= 0 then 1 else -1
			goals.Arms[side] = armGoal(ball + Vector3.new(0, -radius * 0.75, radius * 0.6), Vector3.new(side * 0.25, -0.5, -1), 0.7, "Set", 16)
			goals.Arms[-side] = armGoal(ball + Vector3.new(-side * radius * 1.05, 0, 0.05), Vector3.new(-side, -0.5, 0.1), 0, "Set", 16)
			goals.Pitch = -0.05
			lookAt(rim)
			return goals
		end
		-- Dribbling: the ball hand rides the top of the bounce, the other guards
		local side = if ball.X >= 0 then 1 else -1
		local hold = BALL.HoldOffset.Position
		local handY = math.clamp(ball.Y + radius, hold.Y + radius - ANIM.DribbleHandTravel, hold.Y + radius + 0.1)
		goals.Arms[side] = armGoal(Vector3.new(ball.X, handY, ball.Z), Vector3.new(side * 0.4, -0.2, 0.9), -0.35, "Dribble")
		local o = shoulders[-side]
		goals.Arms[-side] = armGoal(o + Vector3.new(-side * 0.45, -0.45, -0.75) * reach[-side], Vector3.new(-side, -0.6, 0.3), 0, "Guard")
		local speedFraction = math.clamp(flatSpeed / Config.Movement.WalkSpeed, 0, 1)
		goals.Pitch = math.rad(ANIM.DribbleLean) * (0.4 + 0.6 * speedFraction)
		-- Lean into a crossover (or any hard sideways move)
		goals.Roll = math.rad(12) * math.clamp(localVelocity.X / Config.Moves.CrossoverSpeed, -1, 1)
		return goals
	end

	-- 5. Steal reach: a quick jab at the ball
	if track.Move == "Reach" and sinceMove < ANIM.ReachTime then
		local carrier = heldBy[opponentId]
		local target = if carrier then toLocal(carrier.Part.Position) else Vector3.new(0.6, 0, -3)
		local side = if target.X >= -0.2 then 1 else -1
		goals.Arms[side] = armGoal(toward(shoulders[side], target, reach[side] * 1.05), Vector3.new(side * 0.6, -0.8, 0.3), 0, "Reach", 30)
		goals.Pitch = 0.3
		return goals
	end

	-- 6. Just scored: fist pump
	if now - track.ScoredAt < ANIM.FistPumpTime then
		local s = shoulders[1]
		local pump = 0.14 * math.sin((now - track.ScoredAt) * 16)
		-- In proportion to the arm, so big avatars don't hit the elbow's fold limit
		goals.Arms[1] = armGoal(s + Vector3.new(0.17, 0.5 + pump, -0.2) * reach[1], Vector3.new(1, -0.3, 0.4), 0, "Pump", 14)
		goals.Look = Vector3.new(0, 0.3, -1)
		return goals
	end

	-- 7. In the air without the ball: arms up to block or rebound
	if airborne then
		local target: Vector3? = nil
		for _, info in balls do
			if info.State == "Loose" or info.State == "InFlight" then
				local offset = toLocal(info.Part.Position)
				if offset.Magnitude < 7 and offset.Y > 0.5 then
					target = offset
				end
			end
		end
		for side = -1, 1, 2 do
			local s = shoulders[side]
			local aim = if target then target + Vector3.new(side * 0.45, 0, 0) else s + Vector3.new(side * 0.2, 1, -0.3).Unit * reach[side] * 1.1
			goals.Arms[side] = armGoal(toward(s, aim, reach[side] * 1.1), Vector3.new(side, -0.4, 0.4), 0, "Contest", 18)
		end
		return goals
	end

	-- 8. Guarding the ball carrier: arms out, low and wide
	if court and courtState == "Live" and opponentId ~= 0 and heldBy[opponentId] then
		local carrierRoot = rootOf(playerById(opponentId))
		if carrierRoot then
			local offset = toLocal(carrierRoot.Position)
			if Vector3.new(offset.X, 0, offset.Z).Magnitude < ANIM.StanceRange and offset.Z < 0 then
				for side = -1, 1, 2 do
					local s = shoulders[side]
					goals.Arms[side] = armGoal(s + Vector3.new(side * 0.55, -0.45, -0.45) * reach[side], Vector3.new(side * 0.5, -1, 0.4), 0, "Stance", 8)
				end
				goals.Pitch = math.rad(10)
				goals.Look = offset
			end
		end
	end
	return goals
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local SWITCH_TIME = 0.25 -- after changing what an arm does, glide to the new pose this long

local function updateLimb(limb: Limb, goal: ArmGoal?, dt: number, now: number)
	if goal then
		if goal.Layer ~= limb.Layer then
			limb.Layer = goal.Layer
			limb.SwitchedAt = now
		end
		local switching = now - limb.SwitchedAt < SWITCH_TIME
		if limb.Weight <= 1e-3 or not switching then
			-- Starting fresh (the weight does the easing), or carrying on with
			-- the same move: follow the goal exactly, so the hand stays on the ball
			limb.Target, limb.Pole, limb.Flex = goal.Target, goal.Pole, goal.Flex
		else
			-- Just switched moves: glide from the old pose to the new one
			local a = smooth(14, dt)
			limb.Target = limb.Target:Lerp(goal.Target, a)
			limb.Pole = limb.Pole:Lerp(goal.Pole, a)
			limb.Flex += (goal.Flex - limb.Flex) * a
		end
		limb.Weight = math.min(1, limb.Weight + dt * (goal.BlendIn or ANIM.BlendIn))
	else
		limb.Layer = ""
		limb.Weight = math.max(0, limb.Weight - dt * ANIM.BlendOut)
	end
end

local function blend(track: Track, joint: Joint, pose: CFrame, weight: number)
	local base = baseOf(track, joint)
	write(track, joint, base, base:Lerp(pose, weight))
end

local function applyArm(track: Track, arm: Arm, limb: Limb, chest: CFrame)
	if limb.Weight <= 1e-3 then
		restore(track, arm.Shoulder)
		if arm.Elbow then
			restore(track, arm.Elbow :: Joint)
		end
		if arm.Wrist then
			restore(track, arm.Wrist :: Joint)
		end
		return
	end
	local pose = solveArm(arm, chest, limb.Target, limb.Pole, limb.Flex)
	if not pose then
		return
	end
	limb.Shoulder = shoulderOf(chest, arm)
	limb.Reachable = (limb.Target - limb.Shoulder).Magnitude < reachOf(arm) * 0.9
	local w = ease(limb.Weight)
	blend(track, arm.Shoulder, pose.Shoulder, w)
	if arm.Elbow and pose.Elbow then
		blend(track, arm.Elbow, pose.Elbow, w)
	end
	if arm.Wrist and pose.Wrist then
		blend(track, arm.Wrist, pose.Wrist, w)
	end
end

-- Knee up for a layup (thigh raised forward, shin tucked)
local function applyKnee(track: Track, leg: Leg?, weight: number)
	if not leg then
		return
	end
	if weight <= 1e-3 then
		restore(track, leg.Hip)
		if leg.Knee then
			restore(track, leg.Knee :: Joint)
		end
		return
	end
	local w = ease(weight)
	blend(track, leg.Hip, inJoint(leg.Hip, CFrame.Angles(1.15, 0, 0)), w)
	if leg.Knee then
		blend(track, leg.Knee :: Joint, inJoint(leg.Knee :: Joint, CFrame.Angles(-1.4, 0, 0)), w)
	end
end

local function animate(track: Track, rig: Rig, root: BasePart, dt: number, now: number)
	measureVelocity(track, root, dt)
	-- Shoulders from last frame's lean are close enough to plan this frame's goals
	local plannedLean = if math.abs(track.Pitch) + math.abs(track.Roll) > 1e-4 then leanRotation(track.Pitch, track.Roll) else nil
	local plannedChest = chestFrame(track, rig, plannedLean)
	local goals = computeGoals(track, rig, root, plannedChest, dt, now)

	-- Lean (waist on R15; the whole body on R6, so a bit less)
	local leanRate = smooth(10, dt)
	track.Pitch += (goals.Pitch - track.Pitch) * leanRate
	track.Roll += (goals.Roll - track.Roll) * leanRate
	local leaning = math.abs(track.Pitch) + math.abs(track.Roll) > 1e-3
	local lean = if leaning then leanRotation(track.Pitch * (if rig.R6 then 0.5 else 1), track.Roll * (if rig.R6 then 0.5 else 1)) else nil
	local chest, rootT, waistT = chestFrame(track, rig, lean)
	local leanJoint = if rig.R6 then rig.RootJoint else rig.Waist :: Joint
	if leaning then
		local value = if rig.R6 then rootT else waistT :: CFrame
		write(track, leanJoint, baseOf(track, leanJoint), value)
	else
		restore(track, leanJoint)
	end

	for side, arm in { [1] = rig.Right, [-1] = rig.Left } do
		local limb = track.Limbs[side]
		updateLimb(limb, goals.Arms[side], dt, now)
		applyArm(track, arm, limb, chest)
	end

	for side, leg in { [1] = rig.RightLeg, [-1] = rig.LeftLeg } do
		local rate = if goals.Knees[side] then 8 else -5
		track.Knees[side] = math.clamp(track.Knees[side] + rate * dt, 0, 1)
		applyKnee(track, leg, track.Knees[side])
	end

	-- Head follows the ball (or the rim, or the celebration)
	local neck = rig.Neck
	if neck then
		local look = goals.Look
		local wanted = if ANIM.HeadLook and look and look.Magnitude > 1e-3 then 0.7 else 0
		track.LookWeight += (wanted - track.LookWeight) * smooth(6, dt)
		if look and look.Magnitude > 1e-3 then
			track.Look = track.Look:Lerp(look.Unit, smooth(10, dt))
		end
		if track.LookWeight > 0.01 and track.Look.Magnitude > 1e-3 then
			local d = track.Look.Unit
			local yaw = math.clamp(math.atan2(-d.X, -d.Z), -1, 1)
			local pitch = math.clamp(math.asin(math.clamp(d.Y, -1, 1)), -0.6, 0.6)
			local inRoot = CFrame.Angles(0, yaw * track.LookWeight, 0) * CFrame.Angles(pitch * track.LookWeight, 0, 0)
			local chestRot = rotation(chest)
			local base = baseOf(track, neck)
			write(track, neck, base, inJoint(neck, chestRot:Inverse() * inRoot * chestRot) * base)
		else
			restore(track, neck)
		end
	end
end

--------------------------------------------------------------------------------
-- Frame loop
--------------------------------------------------------------------------------

local function readEmote(track: Track, now: number)
	local value = track.Player:GetAttribute(EMOTE_ATTRIBUTE)
	if value == track.EmoteAttribute then
		return
	end
	track.EmoteAttribute = value
	local name = if typeof(value) == "string" then string.match(value, "^(%a+)") else nil
	if name then
		track.Emote, track.EmoteAt = name, now
	end
end

local function readMove(track: Track, now: number)
	local value = track.Player:GetAttribute(MOVE_ATTRIBUTE)
	if value == track.MoveAttribute then
		return
	end
	track.MoveAttribute = value
	if typeof(value) ~= "string" then
		return
	end
	local name = string.match(value, "^(%a+)")
	if name == "Reach" then
		-- Our own reach already played on the key press
		if track.Player == localPlayer and now - localReachAt < 0.6 then
			return
		end
		track.Move, track.MoveAt = "Reach", now
	elseif name == "Ankles" then
		track.Move, track.MoveAt = "Ankles", now
	end
end

local function step(dt: number)
	local now = os.clock()
	dt = math.clamp(dt, 0, 0.1)
	if not ANIM.Enabled then
		for player, track in tracks do
			restoreAll(track)
			tracks[player] = nil
		end
		return
	end
	scanBalls(now)
	scanCourts(now)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local active: { [Player]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local track = getTrack(player)
		active[player] = true
		readMove(track, now)
		readEmote(track, now)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = rootOf(player)
		local visible = character ~= nil and humanoid ~= nil and humanoid.Health > 0 and root ~= nil
			and (root.Position - eye).Magnitude <= ANIM.MaxDistance
		if not visible or not character or not humanoid or not root then
			restoreAll(track)
			track.Rig, track.Character = nil, nil
			continue
		end
		if track.Broken == character then
			continue
		end
		if track.Character ~= character or not track.Rig or not rigIntact(track.Rig :: Rig) then
			restoreAll(track)
			track.Character = character
			track.Rig = buildRig(character, humanoid)
		end
		local rig = track.Rig
		if rig then
			local ok, err = pcall(animate :: any, track, rig, root, dt, now)
			if not ok then
				-- Never break the frame: leave this character to Roblox's own
				-- animations until they respawn, and say so once
				restoreAll(track)
				track.Rig, track.Broken = nil, character
				warn(("[Street Hoops] animation skipped for %s: %s"):format(player.Name, tostring(err)))
			end
		end
	end
	for player, track in tracks do
		if not active[player] then
			restoreAll(track)
			tracks[player] = nil
		end
	end
end

-- Are the poses really showing? With Roblox's fixed-rate simulation on
-- (Workspace > UseFixedSimulation), Transform writes like ours are currently
-- ignored. After physics, check where our own hands ended up; if they keep
-- missing where we put them, say so once in Output.
local applied = { Good = 0, Bad = 0, Warned = false }
local function checkApplied()
	local track = tracks[localPlayer]
	local rig = track and track.Rig
	local root = rootOf(localPlayer)
	if applied.Warned or not track or not rig or not root then
		return
	end
	local now = os.clock()
	local rootCF = root.CFrame
	for side, arm in { [1] = rig.Right, [-1] = rig.Left } do
		local limb = track.Limbs[side]
		local toTarget = limb.Target - limb.Shoulder
		-- (A target straight below the shoulder proves nothing: a hanging arm is there anyway)
		local telling = toTarget.Magnitude > 0.3 and toTarget.Unit.Y > -0.8
		-- (An R6 arm can't bend, so it only has to point the right way)
		if limb.Weight >= 0.99 and (rig.R6 or limb.Reachable) and now - limb.SwitchedAt > SWITCH_TIME + 0.1 and telling then
			local toPalm = rootCF:PointToObjectSpace(arm.Hand.CFrame * palmOf(arm)) - limb.Shoulder
			-- R15 hands land on the target; a straight R6 arm only points at it
			local ok = if rig.R6 then toPalm.Unit:Dot(toTarget.Unit) > 0.97 else (toPalm - toTarget).Magnitude < 0.5
			if ok then
				applied.Good += 1
			else
				applied.Bad += 1
			end
		end
	end
	if applied.Good + applied.Bad >= 90 then
		if applied.Bad > 0.8 * (applied.Good + applied.Bad) then
			applied.Warned = true
			warn("[Street Hoops] ⚠ The body animations aren't showing on your character. Roblox's fixed-rate simulation is probably on: in Explorer select Workspace, and in Properties set UseFixedSimulation to Disabled (README > Troubleshooting).")
		end
		applied.Good, applied.Bad = 0, 0
	end
end

function CharacterAnimator.Init()
	-- Our own reach plays on the key press, not when the server echoes it
	MovesController.LocalMove:Connect(function(name: string)
		if name == "Reach" then
			local track = getTrack(localPlayer)
			localReachAt = os.clock()
			track.Move, track.MoveAt = "Reach", localReachAt
		end
	end)
	-- Every frame after Roblox's Animator has posed the joints (PreSimulation:
	-- earlier writes would be overwritten) and BallVisuals has placed the balls
	BallVisuals.Stepped:Connect(step)
	RunService.Heartbeat:Connect(checkApplied)
end

-- For tests: what the arm on `side` (1 right, -1 left) is doing for a player
function CharacterAnimator.GetArmLayer(player: Player, side: number): string
	local track = tracks[player]
	return if track then track.Limbs[side].Layer else ""
end

-- For tests: the rig finder and arm solver on their own
CharacterAnimator.Solver = { BuildRig = buildRig, SolveArm = solveArm, Reach = reachOf }

return CharacterAnimator
