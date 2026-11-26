--!strict
-- SeedStream: independent deterministic random streams derived from a master seed.
-- Changing vegetation decoration must not reshuffle the mission layout — every subsystem draws
-- from its own stream so perturbing one consumer never perturbs the others.

local SeedStream = {}

-- Stable mix of master seed + stream tag into an independent 31-bit seed.
local function mix(master: number, tag: number): number
	local h = (master * 374761393 + tag * 668265263) % 2147483647
	h = (h * 1274126177) % 2147483647
	if h <= 0 then h += 2147483646 end
	return h
end

local TAGS = {
	geography = 11,
	archetype = 23,
	layout = 37,
	installations = 41,
	cover = 53,
	encounters = 67,
	cosmetic = 71,
	validation = 83,
}

-- Returns a function producing uniform [0,1) draws, backed by Random.new for quality but seeded
-- per-stream so streams are independent.
function SeedStream.stream(master: number, name: string): () -> number
	local tag = TAGS[name] or 97
	local rng = Random.new(mix(master, tag))
	return function()
		return rng:NextNumber()
	end
end

-- Integer stream seed for modules that take numeric seeds directly (noise layers).
function SeedStream.seed(master: number, name: string): number
	return mix(master, TAGS[name] or 97)
end

function SeedStream.tag(name: string): number
	return TAGS[name] or 97
end

return SeedStream
