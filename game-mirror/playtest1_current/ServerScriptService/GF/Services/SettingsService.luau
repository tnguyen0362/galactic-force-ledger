--!strict
-- Player settings: validated on the server, persisted in the profile, published as player attributes so
-- every client system (camera, captions, audio) reads one source instead of inventing its own copy.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require(script.Parent.ProfileService)

local SettingsService = {}

local DEFAULTS = {
	aimSensitivity = 1,
	invertY = false,
	subtitles = true,
	reducedMotion = false,
	volume = 1,
	-- spec S03-041: separate channel volumes, camera shake, touch layout, graphics quality, damage numbers
	musicVolume = 1,
	sfxVolume = 1,
	voiceVolume = 1,
	cameraShake = true,
	touchLayout = "default",
	graphicsQuality = "balanced",
	damageNumbers = true,
}

local RANGES = {
	aimSensitivity = { 0.25, 3 },
	volume = { 0, 1 },
	musicVolume = { 0, 1 },
	sfxVolume = { 0, 1 },
	voiceVolume = { 0, 1 },
}

-- Attribute names are prefixed so nothing collides with gameplay state.
local function attributeFor(key: string): string
	return "GF_Setting_" .. key:sub(1, 1):upper() .. key:sub(2)
end

local function clampNumber(key: string, value: number): number
	local range = RANGES[key]
	if range then
		return math.clamp(value, range[1], range[2])
	end
	return value
end

function SettingsService.snapshot(player: Player): { [string]: any }
	local profile = ProfileService.get(player)
	local stored = profile and profile.settings or nil
	local out = {}
	for key, fallback in pairs(DEFAULTS) do
		local value = stored and stored[key]
		if type(value) == "number" and type(fallback) == "number" then
			out[key] = clampNumber(key, value)
		elseif type(value) == type(fallback) then
			out[key] = value
		else
			out[key] = fallback
		end
	end
	return out
end

function SettingsService.publish(player: Player)
	for key, value in pairs(SettingsService.snapshot(player)) do
		player:SetAttribute(attributeFor(key), value)
	end
end

-- Only known keys are accepted, and only values of the right type. Anything else is ignored rather than
-- written into a persisted profile.
function SettingsService.set(player: Player, key: string, value: any): boolean
	if DEFAULTS[key] == nil then
		return false
	end
	local expected = type(DEFAULTS[key])
	if type(value) ~= expected then
		return false
	end
	if expected == "number" then
		value = clampNumber(key, value)
	end
	local profile = ProfileService.get(player)
	if not profile then
		return false
	end
	profile.settings = profile.settings or {}
	profile.settings[key] = value
	ProfileService.markDirty(player)
	player:SetAttribute(attributeFor(key), value)
	workspace:SetAttribute("GF_SettingsWrites", (workspace:GetAttribute("GF_SettingsWrites") or 0) + 1)
	return true
end

function SettingsService.save(player: Player): boolean
	return ProfileService.save(player)
end

function SettingsService.start()
	local remotes = ReplicatedStorage.GF.Remotes
	local request = remotes:FindFirstChild("RequestSettings")
	if not request then
		request = Instance.new("RemoteEvent")
		request.Name = "RequestSettings"
		request.Parent = remotes
	end
	local changed = remotes:FindFirstChild("SettingsChanged")
	if not changed then
		changed = Instance.new("RemoteEvent")
		changed.Name = "SettingsChanged"
		changed.Parent = remotes
	end
	request.OnServerEvent:Connect(function(player, key, value)
		if not require(script.Parent.NetGuard).allow(player, "default") then
			return
		end
		if key == "read" then
			changed:FireClient(player, SettingsService.snapshot(player))
			return
		end
		if SettingsService.set(player, tostring(key), value) then
			SettingsService.save(player)
			changed:FireClient(player, SettingsService.snapshot(player))
		end
	end)
	for _, player in Players:GetPlayers() do
		SettingsService.publish(player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.delay(2, function()
			if player.Parent then
				SettingsService.publish(player)
			end
		end)
	end)
end

return SettingsService

