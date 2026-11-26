--!strict
-- GeographyService: runtime geographical generation — layer 1 of the hybrid procedural
-- architecture (owner directive 2026-11-25). Deterministic stream G selects:
--   * geographical foundation (real-world elevation crops, genuinely distinct landforms)
--   * orientation (rotation x mirror — legitimate coherence-preserving transforms)
--   * controlled deformation (conservative height-scale jitter, +/-5% max)
-- and reconstructs the terrain at mission init via chunked WriteVoxels (shell-fill writer,
-- fractional occupancy — same quality path as the approved baked prototype).
-- NO raw elevation processing at runtime: all heavy preprocessing is offline; the data
-- modules are delta+b85 compressed heightfields decoded in seconds.

local Terrain = workspace.Terrain
local ServerScriptService = game:GetService("ServerScriptService")

local HeightfieldCodec = require(ServerScriptService.GF.Bake.HeightfieldCodec)
local BakeTerrain = require(ServerScriptService.GF.Bake.BakeTerrain)

local GeographyService = {}

-- foundation registry: fv1 is the approved Teton prototype (regression reference).
-- fv2-fv6 are structurally distinct real-world crops (scan_candidates, gf-geo).
local FOUNDATIONS = {
	{ id = "fv1", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv2", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv3", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv4", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563852 },
	{ id = "fv5", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563852 },
	{ id = "fv6", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	-- cascades volcanic province (mt rainier region): steeper, younger landforms
	{ id = "fv7", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv8", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv9", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
}

export type GeoSpec = {
	foundation: number,
	rotation: number, -- 0..3 (90-degree steps)
	mirror: boolean,
	heightScale: number, -- 0.95..1.05 controlled deformation
	seed: number,
}

-- deterministic stream G: independent of composition/operation streams
function GeographyService.specFromSeed(seed: number): GeoSpec
	local rng = Random.new(seed * 7919 + 13)
	return {
		foundation = rng:NextInteger(1, #FOUNDATIONS),
		rotation = rng:NextInteger(0, 3),
		mirror = rng:NextInteger(0, 1) == 1,
		heightScale = 1 + (rng:NextNumber() - 0.5) * 0.10,
		seed = seed,
	}
end

local function loadFoundation(f: any)
	local dataFolder = ServerScriptService.GF.Bake.Data
	local parts = table.create(f.chunks)
	for i = 0, f.chunks - 1 do
		local mod = dataFolder:FindFirstChild(string.format("%s_d%02d", f.id, i))
		assert(mod, "missing data chunk " .. f.id .. "_d" .. i)
		parts[i + 1] = require(mod)
	end
	local t0 = os.clock()
	local hf = HeightfieldCodec.decode(table.concat(parts), f.n, f.base, f.quant, f.rawlen)
	return hf, os.clock() - t0
end

-- orientation-aware sampler: world x,z -> heightfield lookup with rotation/mirror.
-- heightfield covers 5000 studs centered on origin; spacing 4 studs/sample.
local function orientedSampler(hf: any, spec: GeoSpec)
	local n = hf.n
	local half = 2500
	local scale = spec.heightScale
	return function(x: number, z: number): number
		local u = math.clamp((x + half) / 5000, 0, 1)
		local v = math.clamp((z + half) / 5000, 0, 1)
		if spec.mirror then u = 1 - u end
		local fu, fv
		if spec.rotation == 0 then
			fu, fv = u, v
		elseif spec.rotation == 1 then
			fu, fv = v, 1 - u
		elseif spec.rotation == 2 then
			fu, fv = 1 - u, 1 - v
		else
			fu, fv = 1 - v, u
		end
		return hf.sample(fu * (n - 1), fv * (n - 1)) * scale
	end
end

export type GenResult = {
	spec: GeoSpec,
	decodeTime: number,
	writeTime: number,
	totalTime: number,
	memoryBeforeMb: number,
	memoryAfterMb: number,
	probes: { number },
}

function GeographyService.generate(spec: GeoSpec, opts: any?): GenResult
	local Stats = game:GetService("Stats")
	local memBefore = Stats:GetTotalMemoryUsageMb()
	local t0 = os.clock()

	local f = FOUNDATIONS[spec.foundation]
	local hf, decodeTime = loadFoundation(f)
	local sampler = orientedSampler(hf, spec)

	-- clear any prior terrain, then reconstruct
	Terrain:Clear()
	task.wait() -- let the clear flush before writes begin
	local writeStart = os.clock()
	BakeTerrain.write({
		center = Vector3.new(0, 0, 0),
		size = 5000,
		sampler = sampler,
	})
	local writeTime = os.clock() - writeStart
	local memAfter = Stats:GetTotalMemoryUsageMb()

	-- structural probes for validation: record heights on a fixed lattice
	local probes = {}
	for px = -2, 2 do
		for pz = -2, 2 do
			local x, z = px * 800, pz * 800
			local hit = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -2000, 0))
			table.insert(probes, hit and math.floor(hit.Position.Y + 0.5) or -1)
		end
	end

	local result: GenResult = {
		spec = spec,
		decodeTime = decodeTime,
		writeTime = writeTime,
		totalTime = os.clock() - t0,
		memoryBeforeMb = memBefore,
		memoryAfterMb = memAfter,
		probes = probes,
	}
	print(string.format(
		"GeographyService: %s rot%d mirror=%s scale=%.3f | decode=%.1fs write=%.1fs total=%.1fs mem=%.0f->%.0fMB",
		f.id, spec.rotation, tostring(spec.mirror), spec.heightScale,
		decodeTime, writeTime, result.totalTime, memBefore, memAfter))
	workspace:SetAttribute("GF_GeoFoundation", f.id)
	workspace:SetAttribute("GF_GeoSeed", spec.seed)

	-- terrain analysis for operation placement (directive section 23): the operation
	-- generator consumes candidate sites, valley floor, high ground positions.
	GeographyService.lastSampler = sampler
	GeographyService.lastSpec = spec
	task.spawn(function()
		local ok, err = pcall(function()
			local TerrainAnalysis = require(script.Parent.TerrainAnalysis)
			GeographyService.analysis = TerrainAnalysis.analyze(sampler, 2450, 40)
			if GeographyService.analysis then
				workspace:SetAttribute("GF_GeoAnalyzed", true)
				print(string.format("TerrainAnalysis: %d feasible sites (%d valley, %d high)",
					#GeographyService.analysis.sites, #GeographyService.analysis.valleyFloor, #GeographyService.analysis.highGround))
			end
		end)
		if not ok then warn("TerrainAnalysis failed:", err) end
	end)
	return result
end

GeographyService.lastSampler = nil
GeographyService.lastSpec = nil
GeographyService.analysis = nil

return GeographyService
