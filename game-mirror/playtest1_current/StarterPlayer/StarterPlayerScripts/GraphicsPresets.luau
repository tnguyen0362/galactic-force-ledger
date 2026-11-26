--!strict
-- S15-012/013 graphics presets (Phase 15 rework): Low/Balanced/High are REAL cost tiers now.
-- Gameplay visibility never changes: hitboxes, occlusion, trunk colliders and enemy readability are
-- identical across presets because competitive integrity is not a graphics setting.
--
-- Phase 15 changes:
--  * No longer writes Lighting.FogEnd. Fog distance is owned by BiomeLook/WeatherService on the server
--    (monumental scale); the old 600/900/1400 override flattened every biome's view distance.
--  * foliageDetail has a consumer: server stamps GF_VegTier (1 core, 2 Balanced+, 3 High only) on every
--    planted vegetation instance; lower tiers are parented out of the world on this client only.
--  * Bloom, global shadows and atmosphere haze scale per tier (Atmosphere/Bloom values are multiplied
--    from a captured base each time, never compounded).
--  * Tiers are a perf budget lever, not a performance claim. Xbox One class performance is UNKNOWN
--    until measured on hardware.
local Lighting = game:GetService("Lighting")

type Preset = {
	shadows: boolean,
	weatherDensity: number,
	foliageDetail: number,
	maxVegTier: number,
	bloom: boolean,
	hazeScale: number,
}

local PRESETS: { [string]: Preset } = {
	Low = { shadows = false, weatherDensity = 0.3, foliageDetail = 0.4, maxVegTier = 1, bloom = false, hazeScale = 0.8 },
	Balanced = { shadows = true, weatherDensity = 0.7, foliageDetail = 0.8, maxVegTier = 2, bloom = true, hazeScale = 1.0 },
	High = { shadows = true, weatherDensity = 1.0, foliageDetail = 1.0, maxVegTier = 3, bloom = true, hazeScale = 1.0 },
}

local stash = Instance.new("Folder") -- never parented: holds tier-culled vegetation for this client only
stash.Name = "GFVegStash"
local culled: { [Instance]: Instance } = {} -- inst -> original parent
local currentMax = 3
local vegFolder: Instance? = nil
local baseHaze: number? = nil
local baseBiome: string? = nil

local function tierOf(inst: Instance): number
	local t = inst:GetAttribute("GF_VegTier")
	return type(t) == "number" and t or 1
end

local function cull(inst: Instance)
	if tierOf(inst) > currentMax and not culled[inst] and inst.Parent then
		culled[inst] = inst.Parent
		inst.Parent = stash
	end
end

local function sweep()
	local folder = vegFolder
	if folder then
		local n = 0
		for _, inst in folder:GetChildren() do
			if tierOf(inst) > currentMax then
				cull(inst)
			end
			n += 1
			if n % 400 == 0 then task.wait() end
		end
	end
	-- restore anything now allowed
	local n2 = 0
	for inst, parent in culled do
		if tierOf(inst) <= currentMax and parent.Parent then
			inst.Parent = parent
			culled[inst] = nil
		end
		n2 += 1
		if n2 % 400 == 0 then task.wait() end
	end
end

local function watchFolder(f: Instance)
	vegFolder = f
	f.ChildAdded:Connect(function(child)
		task.defer(cull, child)
	end)
	task.spawn(sweep)
end

local function applyAtmosphere(preset: Preset)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local biome = workspace:GetAttribute("GF_BiomeLook")
	if atmo then
		-- recapture base whenever BiomeLook rewrites the look so scaling never compounds
		if baseHaze == nil or biome ~= baseBiome then
			baseHaze = atmo.Haze
			baseBiome = biome :: any
		end
		atmo.Haze = (baseHaze :: number) * preset.hazeScale
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Enabled = preset.bloom
	end
end

local function applyPreset(name: string)
	local preset = PRESETS[name] or PRESETS.Balanced
	Lighting.GlobalShadows = preset.shadows
	currentMax = preset.maxVegTier
	workspace:SetAttribute("GF_WeatherDensity", preset.weatherDensity)
	workspace:SetAttribute("GF_FoliageDetail", preset.foliageDetail)
	workspace:SetAttribute("GF_GraphicsPreset", name)
	applyAtmosphere(preset)
	task.spawn(sweep)
end

local function currentName(): string
	local n = workspace:GetAttribute("GF_GraphicsPreset")
	return (type(n) == "string" and PRESETS[n]) and n or "Balanced"
end

-- default: Balanced — the spec baseline
applyPreset("Balanced")

-- player selection flows through the settings attribute
workspace:GetAttributeChangedSignal("GF_PlayerGraphicsChoice"):Connect(function()
	local choice = workspace:GetAttribute("GF_PlayerGraphicsChoice")
	if type(choice) == "string" and PRESETS[choice] then
		applyPreset(choice)
	end
end)

-- a new mission re-plants GFVegetation and re-applies BiomeLook: follow both
local function hookVeg(child: Instance)
	if child.Name == "GFVegetation" then
		table.clear(culled)
		watchFolder(child)
	end
end
workspace.ChildAdded:Connect(hookVeg)
local existing = workspace:FindFirstChild("GFVegetation")
if existing then hookVeg(existing) end

workspace:GetAttributeChangedSignal("GF_BiomeLook"):Connect(function()
	baseHaze = nil -- force recapture of the new biome's haze, then re-scale
	task.defer(function() applyAtmosphere(PRESETS[currentName()]) end)
end)
