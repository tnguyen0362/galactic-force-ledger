-- Opening cinematic timeline. 11 shots, 88 seconds at authored playback speed.
-- Camera is station-relative: positions are absolute world studs so the client can tween between them
-- without a second authoring tool.
local Cinematic = {}
Cinematic.Title = "GALACTIC FORCE: COUNTEROFFENSIVE"
Cinematic.Beats = {
	-- Spec segment 0-10: Earth and the peaceful fleet
	{ duration = 10, text = "We crossed the stars believing distance would keep our home safe.",
	  from = Vector3.new(210, 812, 180), to = Vector3.new(150, 796, 120),
	  lookFrom = Vector3.new(0, 770, 0), lookTo = Vector3.new(0, 766, 0) },
	-- Spec segment 10-25: the alien fleet arrives, defenses collapse
	{ duration = 15, text = "Then the Ascendancy came.",
	  from = Vector3.new(120, 786, 96), to = Vector3.new(74, 778, 74),
	  lookFrom = Vector3.new(0, 768, 24), lookTo = Vector3.new(0, 766, 40) },
	-- Spec segment 25-40: occupied Earth, evacuation
	{ duration = 15, text = "Even Earth passed into enemy hands.",
	  from = Vector3.new(0, 775, 62), to = Vector3.new(0, 771, 30),
	  lookFrom = Vector3.new(-58, 776, 0), lookTo = Vector3.new(-20, 770, -14) },
	-- Spec segment 40-57: rebuilding, the human counterattack forms
	{ duration = 17, text = "We rebuilt our fleets.",
	  from = Vector3.new(-30, 770, 6), to = Vector3.new(-14, 768, -18),
	  lookFrom = Vector3.new(0, 762, -34), lookTo = Vector3.new(0, 761, -34) },
	-- Spec segment 57-70: liberation of Earth
	{ duration = 13, text = "Six years ago, Earth was ours again.",
	  from = Vector3.new(0, 766, -26), to = Vector3.new(0, 764, -31),
	  lookFrom = Vector3.new(0, 762, -34), lookTo = Vector3.new(0, 762, -34) },
	-- Spec segment 70-86: the present fleet, equipped soldiers boarding
	{ duration = 16, text = "Earth was not our final victory.",
	  from = Vector3.new(-72, 774, -6), to = Vector3.new(-92, 771, -20),
	  lookFrom = Vector3.new(-96, 770, -30), lookTo = Vector3.new(-96, 770, -34) },
	-- Spec segment 86-95: title and tutorial handoff
	{ duration = 9, text = "The counteroffensive begins now.",
	  from = Vector3.new(0, 772, 0), to = Vector3.new(0, 774, -6),
	  lookFrom = Vector3.new(0, 766, -46), lookTo = Vector3.new(0, 770, -70) },
}
function Cinematic.totalDuration()
	local total = 0
	for _, beat in ipairs(Cinematic.Beats) do
		total += beat.duration
	end
	return total
end
return Cinematic

