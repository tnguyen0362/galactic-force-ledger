-- Opening cinematic timeline. Seven canonical narration beats, 95 seconds total.
-- The client contract remains beats[].duration/text/from/to/lookFrom/lookTo. The added
-- metadata is the authoritative integration contract for the cinematic/audio lanes: chapter
-- cards, intended scene content, skip behavior, voice routing and music ducking. Positions are
-- absolute world studs around the GFS Vanguard concourse so playback is useful even before the
-- final Earth/invasion scene set exists.
local Cinematic = {}

Cinematic.Version = 2
Cinematic.Title = "GALACTIC FORCE: COUNTEROFFENSIVE"
Cinematic.Speaker = "Commander Elara Voss"
Cinematic.TriggerRemote = "IntroReplay"
Cinematic.CompletionRemote = "MarkIntroSeen"
Cinematic.ReplayRemote = "RequestIntroReplay"

-- Spec contract: skip is intentional, never a stray keypress, and does not skip First Spear.
-- CinematicUI currently implements keyboard skip; gamepad/touch hold widgets are client-lane work.
Cinematic.Skip = {
	holdSeconds = 1.2,
	keyboard = { "Space", "Escape" },
	gamepad = { "ButtonX", "ButtonStart" },
	touchButton = "HOLD TO SKIP TRANSMISSION",
}

-- Voice must be optional at runtime: subtitles carry the story if approved recordings are absent.
Cinematic.Audio = {
	voiceChannel = "voice",
	duckMusicTo = 0.35,
	duckSeconds = 0.35,
	missingVoiceAssets = true,
	temporaryToneAllowed = true,
}

Cinematic.ReducedMotion = {
	staticBeatFrames = true,
	noContinuousRoll = true,
}

Cinematic.Beats = {
	-- 0-10 s — THE AGE OF EXPANSION: Earth's blue curvature, exploration ships, distant colonies.
	{
		id = "age_of_expansion",
		chapter = "THE AGE OF EXPANSION",
		visual = "Earth curvature; peaceful human exploration formation; colony montage",
		duration = 10,
		speaker = Cinematic.Speaker,
		text = "We crossed the stars believing distance would keep our home safe.",
		from = Vector3.new(-44, 771.5, 4), to = Vector3.new(-18, 770.5, -4),
		lookFrom = Vector3.new(-8, 769, -76), lookTo = Vector3.new(6, 768, -76),
	},
	-- 10-25 s — THE FIRST STRIKE: alien silhouettes arrive, emergency displays, defenses collapse.
	{
		id = "first_strike",
		chapter = "THE FIRST STRIKE",
		visual = "Ascendancy fleet silhouettes over Earth; interference; orbital defense flashes",
		duration = 15,
		speaker = Cinematic.Speaker,
		text = "Then the Ascendancy came. Without warning. Without surrender terms. Their fleets shattered our defenses and carried the war to Earth.",
		from = Vector3.new(48, 775, 22), to = Vector3.new(34, 772, 8),
		lookFrom = Vector3.new(8, 770, -76), lookTo = Vector3.new(-8, 768, -76),
	},
	-- 25-40 s — EARTH OCCUPIED: evacuation, smoke-shrouded coastline, alien patrol silhouettes.
	{
		id = "earth_occupied",
		chapter = "EARTH OCCUPIED",
		visual = "occupied coastline; evacuation columns; Ascendancy patrol in a ruined city",
		duration = 15,
		speaker = Cinematic.Speaker,
		text = "Our worlds fell. Our fleets broke. Even Earth passed into enemy hands.",
		from = Vector3.new(36, 770, -28), to = Vector3.new(30, 769.2, -52),
		lookFrom = Vector3.new(0, 766, -90), lookTo = Vector3.new(0, 765, -110),
	},
	-- 40-57 s — WE HELD: refit hangars, welders, soldiers, red sectors turning blue.
	{
		id = "we_held",
		chapter = "WE HELD",
		visual = "fleet refit hangars; armored troopers mustering; tactical display changing red to blue",
		duration = 17,
		speaker = Cinematic.Speaker,
		text = "We did not disappear. We rebuilt our fleets. Reclaimed our strength. And fought for every kilometer.",
		from = Vector3.new(30, 773, -6), to = Vector3.new(14, 770, -16),
		lookFrom = Vector3.new(0, 768, -34), lookTo = Vector3.new(0, 768, -34),
	},
	-- 57-70 s — EARTH RECLAIMED: breach, orbital fleet in sunrise, enemy emblem dark, flag raised.
	{
		id = "earth_reclaimed",
		chapter = "EARTH RECLAIMED",
		visual = "human breach teams; fleet emerging into sunrise; Galactic Force flag over skyline",
		duration = 13,
		speaker = Cinematic.Speaker,
		text = "Six years ago, Earth was ours again.",
		from = Vector3.new(-55, 773, -12), to = Vector3.new(-28, 771, -4),
		lookFrom = Vector3.new(-10, 769, -78), lookTo = Vector3.new(4, 768, -78),
	},
	-- 70-86 s — THE COUNTEROFFENSIVE: operations station, war table, armor/weapons, boarding.
	{
		id = "counteroffensive",
		chapter = "THE COUNTEROFFENSIVE",
		visual = "GFS Vanguard war table; helmet and rifle preparation; soldiers boarding a drop craft",
		duration = 16,
		speaker = Cinematic.Speaker,
		text = "But millions still live beneath Ascendancy occupation. Earth was not our final victory. It was the beginning of their defeat.",
		from = Vector3.new(-86, 771, 8), to = Vector3.new(16, 772, 48),
		lookFrom = Vector3.new(-113, 767, 0), lookTo = Vector3.new(0, 767, 74),
	},
	-- 86-95 s — TITLE AND HANDOFF: fleet silhouette behind planet, title card, tutorial transition.
	{
		id = "title_handoff",
		chapter = "THE COUNTEROFFENSIVE BEGINS",
		visual = "wide fleet silhouette behind a planet; clean institutional title; seamless First Spear handoff",
		duration = 9,
		speaker = Cinematic.Speaker,
		text = "Galactic Force. The counteroffensive begins now. Report for deployment.",
		from = Vector3.new(0, 774, 58), to = Vector3.new(0, 772, 36),
		lookFrom = Vector3.new(0, 768, -34), lookTo = Vector3.new(0, 769, -74),
	},
}

function Cinematic.totalDuration()
	local total = 0
	for _, beat in ipairs(Cinematic.Beats) do
		total += beat.duration
	end
	return total
end

return Cinematic
