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
}

local DEFAULTS: GripProfile = {
	primaryGrip = Vector3.new(0, -0.1, 0.1),
	supportGrip = Vector3.new(0, -0.12, -0.55),
	length = 1.0,
}

-- Posture offsets in ROOT space (character-local, -Z forward). Refined from the legacy
-- hip/ADS offsets which read correctly at camera but were never gripped.
local POSES = {
	-- combat ready / aim: weapon raised, stock toward shoulder line, barrel forward
	aim = {
		cf = CFrame.new(0.55, -0.35, -0.85),
	},
	-- exploration/low-ready: weapon lowered across the body
	ready = {
		cf = CFrame.new(0.62, -0.75, -0.55) * CFrame.Angles(math.rad(-18), 0, 0),
	},
}

function WeaponPose.gripProfile(weaponId: string): GripProfile
	-- v1: shared geometry; Gate B measures per-weapon from actual models
	return DEFAULTS
end

-- Compute the weapon world transform.
-- rootCf: HumanoidRootPart world CFrame. aiming: posture selector.
-- aimYaw/aimPitch: optional torso-independent aim angles (rad) for upper-body aim decomposition.
function WeaponPose.weaponWorld(rootCf: CFrame, aiming: boolean, aimYaw: number?, aimPitch: number?): CFrame
	local pose = aiming and POSES.aim or POSES.ready
	local cf = rootCf * pose.cf
	if aiming and aimPitch then
		-- weapon follows vertical aim; horizontal follows the root for v1 (torso yaw layered later)
		cf = cf * CFrame.Angles(-(aimPitch or 0), 0, 0)
	end
	return cf
end

-- World position of a grip point given the weapon transform.
function WeaponPose.gripWorld(weaponCf: CFrame, grip: Vector3): Vector3
	return (weaponCf * CFrame.new(grip)).Position
end

return WeaponPose
