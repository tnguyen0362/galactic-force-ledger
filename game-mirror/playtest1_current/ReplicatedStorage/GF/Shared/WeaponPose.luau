--!strict
-- WeaponPose: single source of truth for the equipped weapon's world transform.
-- Phase 12 architecture (spec §33-35): the weapon pose is authored in character space from
-- posture state; BOTH the client viewmodel placement AND the server arm-IK targets derive
-- from this same math, so visual weapon and arm contact targets can never diverge.
--
-- The weapon leads, the hands follow: arms are IK'd onto the weapon's grip points,
-- not the reverse. This replaces the legacy torso-pinned float where arms ignored the gun.

local WeaponPose = {}

-- Per-weapon grip geometry (studs, weapon-local: -Z is barrel-forward in weapon space).
-- v1 values measured from the part-built models in WeaponVisuals; per-weapon refinement
-- is a Gate B deliverable. primaryGrip = right-hand contact, supportGrip = left-hand.
export type GripProfile = {
	primaryGrip: Vector3,
	supportGrip: Vector3,
	length: number,
	twoHanded: boolean?,
	magazineGrip: Vector3?,
}

local DEFAULTS: GripProfile = {
	primaryGrip = Vector3.new(0, -0.1, 0.1),
	supportGrip = Vector3.new(0, -0.12, -0.55),
	length = 1.0,
	twoHanded = true,
}

-- Per-weapon grip geometry measured from the WeaponVisuals part layouts (Gate B).
-- primaryGrip = the swept polymer pistol-grip part; supportGrip = handguard/forend/pump,
-- clamped to the reach envelope validated by the offline study (<=0.65 forward of primary).
-- P01 is a sidearm: one-handed, left arm stays free (twoHanded = false).
local PROFILES: { [string]: GripProfile } = {
	AR01 = { primaryGrip = Vector3.new(0, -0.16, 0.12), supportGrip = Vector3.new(0, -0.08, -0.5), magazineGrip = Vector3.new(0, -0.21, -0.38), length = 1.6, twoHanded = true },
	SMG03 = { primaryGrip = Vector3.new(0, -0.14, 0.05), supportGrip = Vector3.new(0, -0.1, -0.35), magazineGrip = Vector3.new(0, -0.24, -0.28), length = 0.95, twoHanded = true },
	LMG12 = { primaryGrip = Vector3.new(0, -0.18, 0.05), supportGrip = Vector3.new(0, -0.14, -0.6), magazineGrip = Vector3.new(0, -0.28, -0.15), length = 1.8, twoHanded = true },
	SG04 = { primaryGrip = Vector3.new(0, -0.15, 0.12), supportGrip = Vector3.new(0, -0.06, -0.45), magazineGrip = Vector3.new(0, -0.15, -0.1), length = 1.25, twoHanded = true },
	MR07 = { primaryGrip = Vector3.new(0, -0.14, 0.08), supportGrip = Vector3.new(0, -0.06, -0.5), magazineGrip = Vector3.new(0, -0.2, -0.28), length = 2.0, twoHanded = true },
	GL22 = { primaryGrip = Vector3.new(0, -0.16, 0.15), supportGrip = Vector3.new(0, -0.1, -0.45), magazineGrip = Vector3.new(0, -0.04, -0.25), length = 1.0, twoHanded = true },
	RL09 = { primaryGrip = Vector3.new(0, -0.18, 0.12), supportGrip = Vector3.new(0, -0.08, -0.5), magazineGrip = Vector3.new(0, -0.1, 0.05), length = 1.9, twoHanded = true },
	P01 = { primaryGrip = Vector3.new(0, -0.14, 0.08), supportGrip = Vector3.new(0, 0, 0), magazineGrip = Vector3.new(0, -0.18, 0.08), length = 0.5, twoHanded = false },
}

-- Posture offsets in ROOT space (character-local, -Z forward). Refined from the legacy
-- hip/ADS offsets which read correctly at camera but were never gripped.
local POSES = {
	-- combat aim: raised version of the ready hold (refined further in aim decomposition)
	aim = {
		cf = CFrame.new(0.27, 0.40, -0.55) * CFrame.Angles(0, math.rad(15), 0),
	},
	-- sprint: weapon tucked low and inward, muzzle down — one-hand carry illusion,
	-- both grips still technically reachable but arms mostly relax (CCD handles it)
	sprint = {
		cf = CFrame.new(0.45, -0.35, -0.45) * CFrame.Angles(0, math.rad(30), 0) * CFrame.Angles(math.rad(-35), 0, 0),
	},
	-- low-ready: numerically solved for two-arm reachability (offline reach study):
	-- weapon yawed 15 deg cross-body, pitched 10 deg down, receiver at chest-right.
	-- REQUIRES the bladed torso stance (25 deg waist yaw when armed) — without it the
	-- support grip is beyond left-arm reach (measured 2.67 studs vs 1.89 max reach).
	ready = {
		cf = CFrame.new(0.39, 0.03, -0.61) * CFrame.Angles(0, math.rad(15), 0) * CFrame.Angles(math.rad(-10), 0, 0),
	},
}

function WeaponPose.gripProfile(weaponId: string): GripProfile
	return PROFILES[weaponId] or DEFAULTS
end

-- Compute the weapon world transform.
-- rootCf: HumanoidRootPart world CFrame. aiming: posture selector.
-- aimYaw/aimPitch: optional torso-independent aim angles (rad) for upper-body aim decomposition.
function WeaponPose.weaponWorld(rootCf: CFrame, aiming: boolean, aimYaw: number?, aimPitch: number?, sprinting: boolean?, reloading: boolean?, switchBlend: number?): CFrame
	local pose = POSES.ready
	if aiming then
		pose = POSES.aim
	elseif sprinting then
		pose = POSES.sprint
	end
	local cf = rootCf * pose.cf
	if switchBlend and switchBlend > 0 then
		-- weapon switch: dip down/in as the swap progresses (0 = raised, 1 = fully lowered)
		cf = cf * CFrame.new(0, -0.45 * switchBlend, 0.2 * switchBlend) * CFrame.Angles(math.rad(-40) * switchBlend, 0, 0)
	end
	if reloading and not aiming then
		-- reload presentation: weapon rolls inward and down so the support hand can work the magazine
		cf = cf * CFrame.Angles(math.rad(-28), math.rad(10), math.rad(-15))
	end
	if aiming and aimPitch then
		-- weapon follows vertical aim exactly (authoritative); the torso carries ~30%
		-- of the pitch via the waist joint so the arms absorb only the remainder.
		cf = cf * CFrame.Angles(aimPitch, 0, 0)
	end
	return cf
end

-- World position of a grip point given the weapon transform.
function WeaponPose.gripWorld(weaponCf: CFrame, grip: Vector3): Vector3
	return (weaponCf * CFrame.new(grip)).Position
end

return WeaponPose
