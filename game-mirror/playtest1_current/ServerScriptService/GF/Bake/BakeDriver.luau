--!strict
-- BakeDriver: offline terrain foundation bake (edit-mode tooling, not runtime).
-- Decodes the full-res Teton foundation heightfield once per Studio session (cached in
-- shared state), then writes terrain slices via BakeTerrain. Invoke from MCP execute:
--   require(...Bake.BakeDriver).slice(tx0, tx1, tz0, tz1)
local BakeDriver = {}

local EXTENT = 5000 -- studs, battlefield width
local N = 1250      -- heightfield samples per side
local RAWLEN = 1563750 + ((-1563750) % 4) -- padded raw length matches exporter
local BASE = 24.0
local QUANT = 0.25

local function shared(): any
	local sh = (getfenv and nil) or nil
	-- edit-mode plugin context: use _G-style shared table
	return shared
end

local cache: any = nil

local function decodeOnce()
	if cache then return cache end
	local t0 = os.clock()
	local dataFolder = script.Parent:WaitForChild("Data")
	local chunks = {}
	for _, m in dataFolder:GetChildren() do
		if m:IsA("ModuleScript") then
			table.insert(chunks, { name = m.Name, src = require(m) })
		end
	end
	table.sort(chunks, function(a, b) return a.name < b.name end)
	local parts = {}
	for _, c in chunks do table.insert(parts, c.src) end
	local data = table.concat(parts)
	print(string.format("BakeDriver: data assembled %d chars from %d chunks", #data, #chunks))
	local codec = require(script.Parent:WaitForChild("HeightfieldCodec"))
	local rawlen = 1563750 -- unpadded truth length; decoder stops at rawlen
	local hf = codec.decode(data, N, BASE, QUANT, rawlen)
	print(string.format("BakeDriver: heightfield decoded in %.1fs", os.clock() - t0))
	cache = hf
	return hf
end

function BakeDriver.sampler()
	local hf = decodeOnce()
	-- stud coords -> fractional grid coords. grid covers -EXTENT/2 .. +EXTENT/2
	return function(x: number, z: number): number
		local gx = (x + EXTENT / 2) / EXTENT * (N - 1)
		local gz = (z + EXTENT / 2) / EXTENT * (N - 1)
		return hf.sample(gx, gz)
	end
end

function BakeDriver.slice(tx0: number, tx1: number, tz0: number, tz1: number)
	local bake = require(script.Parent:WaitForChild("BakeTerrain"))
	bake.write({
		center = Vector3.new(0, 0, 0),
		size = EXTENT,
		sampler = BakeDriver.sampler(),
		tx0 = tx0, tx1 = tx1, tz0 = tz0, tz1 = tz1,
	})
	return "slice done"
end

-- quick single-tile probe for cost measurement
function BakeDriver.probe(tx: number, tz: number)
	return BakeDriver.slice(tx, tx, tz, tz)
end

return BakeDriver
