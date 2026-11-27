--!strict
-- GFAudio: zero-upload audio layer. All sounds are client-side, pooled, and
-- built from engine-bundled rbxasset sounds re-pitched per event. No uploaded
-- assets, no server cost, no replication.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- ---------------------------------------------------------------------------
-- AMBIENT BED ASSET SLOTS
-- No authored ambient-loop uploads exist anywhere in this repository. These
-- constants intentionally reuse engine-bundled sounds already referenced by
-- the combat/UI mix; drop approved ambient asset ids into these slots when they exist.
-- Do not invent numeric ids — unloaded audio fails silently in production.
-- ---------------------------------------------------------------------------
local STATION_OPS_BED_ID = "rbxasset://sounds/bass.wav"
local STATION_CONSOLE_BED_ID = "rbxasset://sounds/electronicpingshort.wav"
local MISSION_WIND_BED_ID = "rbxasset://sounds/bass.wav"

local GFAudio = {}

local MAX_VOICES = 14
local pool: { Sound } = {}
local anchors: { [Sound]: BasePart } = {}
local nextVoice = 1
local anchorSerial = 0
-- Reuse a single voice folder: this module may be instantiated more than once
-- (Studio tooling and the game share the place), and duplicate folders would
-- split the pool and hide voices from measurement.
local existing = SoundService:FindFirstChild("GFAudioVoices")
local root: Folder = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
if not root.Parent then
	root.Name = "GFAudioVoices"
	root.Parent = SoundService
end

-- event -> base asset, pitch range, volume, rolloff
local EVENTS = {
	rifle_fire     = { id = "rbxasset://sounds/metal.ogg",                pitch = { 1.55, 1.95 }, volume = 0.38, range = 130 },
	shotgun_fire   = { id = "rbxasset://sounds/bass.wav",                pitch = { 1.20, 1.45 }, volume = 0.52, range = 140 },
	-- class-distinct voices shaped from the stock set: pistol is a lighter snap, marksman a heavy
	-- low crack, LMG a chugging mid, SMG a rapid high tick, launchers a deep whomp. Same assets,
	-- different envelopes — identity comes from consistency, not from unique samples.
	pistol_fire    = { id = "rbxasset://sounds/metal.ogg",                pitch = { 2.00, 2.30 }, volume = 0.30, range = 100 },
	marksman_fire  = { id = "rbxasset://sounds/metal.ogg",                pitch = { 0.85, 1.00 }, volume = 0.50, range = 180 },
	lmg_fire       = { id = "rbxasset://sounds/metal.ogg",                pitch = { 1.25, 1.45 }, volume = 0.42, range = 140 },
	smg_fire       = { id = "rbxasset://sounds/metal.ogg",                pitch = { 2.10, 2.40 }, volume = 0.28, range = 95 },
	launcher_fire  = { id = "rbxasset://sounds/bass.wav",                pitch = { 0.70, 0.85 }, volume = 0.55, range = 160 },
	hit_flesh      = { id = "rbxasset://sounds/snap.wav",                pitch = { 0.72, 0.92 }, volume = 0.28, range = 90 },
	hit_surface    = { id = "rbxasset://sounds/snap.wav",                pitch = { 1.05, 1.28 }, volume = 0.16, range = 70 },
	hit_shield     = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = { 1.05, 1.30 }, volume = 0.30, range = 80 },
	enemy_death    = { id = "rbxasset://sounds/metal.ogg",              pitch = { 0.55, 0.72 }, volume = 0.36, range = 110 },
	player_hurt    = { id = "rbxasset://sounds/bass.wav",                pitch = { 0.72, 0.88 }, volume = 0.24, range = 40 },
	reload         = { id = "rbxasset://sounds/switch3.wav",             pitch = { 0.95, 1.05 }, volume = 0.32, range = 45 },
	reload_start   = { id = "rbxasset://sounds/clickfast.wav",           pitch = { 1.00, 1.10 }, volume = 0.30, range = 45 },
	footstep       = { id = "rbxasset://sounds/snap.wav",                pitch = { 1.35, 1.75 }, volume = 0.13, range = 45 },
	jump           = { id = "rbxasset://sounds/action_jump.mp3",         pitch = { 1.00, 1.05 }, volume = 0.22, range = 45 },
	land           = { id = "rbxasset://sounds/action_get_up.mp3",       pitch = { 0.95, 1.05 }, volume = 0.26, range = 50 },
	ui_click       = { id = "rbxasset://sounds/button.wav",              pitch = { 1.00, 1.00 }, volume = 0.35, range = 0 },
	shield_break   = { id = "rbxasset://sounds/glassbreak.wav",           pitch = { 1.30, 1.50 }, volume = 0.55, range = 0 },
	ui_confirm     = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = { 0.70, 0.75 }, volume = 0.38, range = 0 },
	rare_loot      = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = { 0.92, 1.04 }, volume = 0.30, range = 0 },
	objective_done = { id = "rbxasset://sounds/bass.wav",                pitch = { 0.80, 0.85 }, volume = 0.45, range = 0 },
	mission_fail   = { id = "rbxasset://sounds/glassbreak.wav",          pitch = { 0.60, 0.65 }, volume = 0.40, range = 0 },
}

local LOOPS = {
	-- Scene beds. The lobby is a low operations-room hum with an almost imperceptible
	-- console detail layer; the mission surface is a separate open-air low wind bed.
	station_ops       = { id = STATION_OPS_BED_ID,      pitch = 0.18, volume = 0.055, channel = "music", eq = { low = 4, mid = -14, high = -30 } },
	station_console   = { id = STATION_CONSOLE_BED_ID,  pitch = 0.14, volume = 0.014, channel = "music", eq = { low = -18, mid = -4, high = -8 } },
	mission_wind      = { id = MISSION_WIND_BED_ID,     pitch = 0.34, volume = 0.075, channel = "music", eq = { low = -6, mid = 1, high = -10 } },
	-- Backwards-compatible name retained for older callers; new scene direction uses mission_wind.
	ambient_wind      = { id = MISSION_WIND_BED_ID,     pitch = 0.35, volume = 0.070, channel = "music" },
	extraction_hum    = { id = "rbxasset://sounds/bass.wav", pitch = 0.22, volume = 0.10, channel = "sfx" },
	relay_hum         = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.30, volume = 0.05, channel = "sfx" },
}

local loopVoices: { [string]: Sound } = {}
local loopLevels: { [string]: number } = {}
local loopTweens: { [string]: Tween } = {}

local function takeVoice(): Sound
	if #pool < MAX_VOICES then
		local s = Instance.new("Sound")
		s.Name = "Voice" .. (#pool + 1)
		s.Parent = root
		table.insert(pool, s)
		return s
	end
	local s = pool[nextVoice]
	nextVoice = (nextVoice % MAX_VOICES) + 1
	return s
end

-- Master volume from the profile settings. One helper so every voice and loop obeys it.
local function masterVolume(): number
	local player = game:GetService("Players").LocalPlayer
	local value = player and tonumber(player:GetAttribute("GF_Setting_Volume")) or 1
	return math.clamp(value or 1, 0, 1)
end

-- Per-channel volumes (spec S03-041): sfx scales effect voices, voice scales commander lines,
-- music scales the music state loops. Each reads its own server-validated setting attribute.
local function channelVolume(channel: string): number
	local player = game:GetService("Players").LocalPlayer
	if not player then
		return 1
	end
	local attr = channel == "sfx" and "GF_Setting_SfxVolume"
		or channel == "voice" and "GF_Setting_VoiceVolume"
		or channel == "music" and "GF_Setting_MusicVolume"
		or nil
	if not attr then
		return 1
	end
	return math.clamp(tonumber(player:GetAttribute(attr)) or 1, 0, 1)
end
GFAudio.channelVolume = channelVolume

GFAudio.masterVolume = masterVolume

local function loopLevel(name: string): number
	local level = loopLevels[name]
	if level == nil then
		return 1
	end
	return math.clamp(level, 0, 1)
end

local function targetLoopVolume(name: string): number
	local cfg = LOOPS[name]
	if not cfg then
		return 0
	end
	return cfg.volume * loopLevel(name) * masterVolume() * channelVolume(cfg.channel or "sfx")
end

local function cancelLoopTween(name: string)
	local tween = loopTweens[name]
	if tween then
		tween:Cancel()
		loopTweens[name] = nil
	end
end

local function applyLoopVolume(name: string, fadeTime: number?)
	local voice = loopVoices[name]
	if not voice then
		return
	end
	cancelLoopTween(name)
	local target = targetLoopVolume(name)
	local duration = math.max(0, fadeTime or 0)
	if duration <= 0 then
		voice.Volume = target
		return
	end
	local tween = TweenService:Create(voice, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = target })
	loopTweens[name] = tween
	tween.Completed:Connect(function()
		if loopTweens[name] == tween then
			loopTweens[name] = nil
		end
	end)
	tween:Play()
end

-- Scene direction API: level 0 keeps a bed allocated but silent, level 1 is its authored
-- volume. Runtime uses this for station/mission crossfades; proximity loops can ignore it.
function GFAudio.setLoopLevel(name: string, level: number, fadeTime: number?)
	if not LOOPS[name] then
		return
	end
	loopLevels[name] = math.clamp(level, 0, 1)
	applyLoopVolume(name, fadeTime or 0.25)
end

-- Settings are player attributes, not events. The runtime calls this when any volume
-- attribute changes so long-running beds track the settings panel immediately.
function GFAudio.refreshLoopVolumes()
	for name in loopVoices do
		applyLoopVolume(name, 0.12)
	end
end

function GFAudio.play(eventName: string, position: Vector3?, volumeScale: number?, pitchScale: number?)
	local cfg = EVENTS[eventName]
	if not cfg then
		return nil
	end
	-- audit counter: makes "did this cue actually fire" a number instead of a race
	local counter = "count_" .. eventName
	root:SetAttribute(counter, (root:GetAttribute(counter) or 0) + 1)
	local voice = takeVoice()
	voice.SoundId = cfg.id
	voice.PlaybackSpeed = (cfg.pitch[1] + math.random() * (cfg.pitch[2] - cfg.pitch[1])) * (pitchScale or 1)
	voice.Volume = cfg.volume * (volumeScale or 1) * masterVolume() * channelVolume("sfx")
	voice.Looped = false
	voice.RollOffMode = Enum.RollOffMode.InverseTapered
	voice.RollOffMaxDistance = math.max(cfg.range, 1)
	voice.RollOffMinDistance = 12
	if position and cfg.range > 0 then
		local anchor = anchors[voice]
		if not anchor then
			anchor = Instance.new("Part")
			anchorSerial += 1
			anchor.Name = "GFAudioAnchor_" .. anchorSerial
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.CastShadow = false
			anchor.Transparency = 1
			anchor.Size = Vector3.new(0.2, 0.2, 0.2)
			anchor.Parent = (function()
				local f = workspace:FindFirstChild("GFAudioAnchors")
				if not f then
					f = Instance.new("Folder")
					f.Name = "GFAudioAnchors"
					f.Parent = workspace
				end
				return f
			end)()
			anchors[voice] = anchor
		end
		anchor.Position = position
		voice.Parent = anchor
	else
		voice.Parent = root
	end
	voice:Play()
	return voice
end

function GFAudio.startLoop(name: string, parent: Instance?): Sound?
	local cfg = LOOPS[name]
	if not cfg then
		return nil
	end
	local loopCounter = "count_loop_" .. name
	root:SetAttribute(loopCounter, (root:GetAttribute(loopCounter) or 0) + 1)
	local current = loopVoices[name]
	if current then
		return current
	end
	if loopLevels[name] == nil then
		loopLevels[name] = 1
	end
	local s = Instance.new("Sound")
	s.Name = "Loop_" .. name
	s.SoundId = cfg.id
	s.PlaybackSpeed = cfg.pitch
	s.Volume = targetLoopVolume(name)
	s.Looped = true
	if cfg.eq then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.Name = "AmbienceEQ"
		eq.LowGain = cfg.eq.low or 0
		eq.MidGain = cfg.eq.mid or 0
		eq.HighGain = cfg.eq.high or 0
		eq.Parent = s
	end
	s.Parent = parent or SoundService
	s:Play()
	loopVoices[name] = s
	return s
end

function GFAudio.stopLoop(name: string)
	cancelLoopTween(name)
	local s = loopVoices[name]
	if s then
		s:Destroy()
		loopVoices[name] = nil
	end
end

function GFAudio.stopAll()
	for _, s in pool do
		s:Stop()
	end
	for name in loopVoices do
		GFAudio.stopLoop(name)
	end
end

function GFAudio.debugStats()
	local playing = 0
	for _, s in pool do
		if s.IsPlaying then
			playing += 1
		end
	end
	local loops = 0
	for _ in loopVoices do
		loops += 1
	end
	return { voices = #pool, playing = playing, loops = loops, max = MAX_VOICES, events = (function() local n = 0 for _ in EVENTS do n += 1 end return n end)() }
end

return GFAudio

