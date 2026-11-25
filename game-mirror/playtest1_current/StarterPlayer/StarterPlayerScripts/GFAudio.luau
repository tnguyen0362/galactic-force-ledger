--!strict
-- GFAudio: zero-upload audio layer. All sounds are client-side, pooled, and
-- built from engine-bundled rbxasset sounds re-pitched per event. No uploaded
-- assets, no server cost, no replication.

local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

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
	hit_flesh      = { id = "rbxasset://sounds/impact_water.mp3",        pitch = { 1.45, 1.85 }, volume = 0.42, range = 90 },
	hit_shield     = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = { 1.05, 1.30 }, volume = 0.30, range = 80 },
	enemy_death    = { id = "rbxasset://sounds/uuhhh.mp3",               pitch = { 0.75, 0.95 }, volume = 0.45, range = 110 },
	player_hurt    = { id = "rbxasset://sounds/uuhhh.mp3",               pitch = { 1.20, 1.30 }, volume = 0.50, range = 40 },
	reload         = { id = "rbxasset://sounds/switch3.wav",             pitch = { 0.95, 1.05 }, volume = 0.32, range = 45 },
	reload_start   = { id = "rbxasset://sounds/clickfast.wav",           pitch = { 1.00, 1.10 }, volume = 0.30, range = 45 },
	footstep       = { id = "rbxasset://sounds/snap.wav",                pitch = { 1.35, 1.75 }, volume = 0.13, range = 45 },
	jump           = { id = "rbxasset://sounds/action_jump.mp3",         pitch = { 1.00, 1.05 }, volume = 0.22, range = 45 },
	land           = { id = "rbxasset://sounds/action_get_up.mp3",       pitch = { 0.95, 1.05 }, volume = 0.26, range = 50 },
	ui_click       = { id = "rbxasset://sounds/button.wav",              pitch = { 1.00, 1.00 }, volume = 0.35, range = 0 },
	shield_break   = { id = "rbxasset://sounds/glassbreak.wav",           pitch = { 1.30, 1.50 }, volume = 0.55, range = 0 },
	ui_confirm     = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = { 0.70, 0.75 }, volume = 0.38, range = 0 },
	objective_done = { id = "rbxasset://sounds/bass.wav",                pitch = { 0.80, 0.85 }, volume = 0.45, range = 0 },
	mission_fail   = { id = "rbxasset://sounds/glassbreak.wav",          pitch = { 0.60, 0.65 }, volume = 0.40, range = 0 },
}

local LOOPS = {
	ambient_wind    = { id = "rbxasset://sounds/bass.wav",         pitch = 0.35, volume = 0.07 },
	extraction_hum  = { id = "rbxasset://sounds/bass.wav",         pitch = 0.22, volume = 0.10 },
	relay_hum       = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.30, volume = 0.05 },
}

local loopVoices: { [string]: Sound } = {}

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
	local s = Instance.new("Sound")
	s.Name = "Loop_" .. name
	s.SoundId = cfg.id
	s.PlaybackSpeed = cfg.pitch
	s.Volume = cfg.volume * masterVolume() * channelVolume("sfx")
	s.Looped = true
	s.Parent = parent or SoundService
	s:Play()
	loopVoices[name] = s
	return s
end

function GFAudio.stopLoop(name: string)
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

