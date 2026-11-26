--!strict
-- SeedStream: independent deterministic random streams derived from a master seed.
-- Changing vegetation decoration must not reshuffle the mission layout — every subsystem draws
-- from its own stream so perturbing one consumer never perturbs the others.

local SeedStream = {}

-- Exact 32-bit multiply mod 2^32 via 16-bit splits (all intermediates < 2^53, exact in doubles).
-- Needed because Luau numbers are doubles: naive a*b % 2^32 loses low bits for large products.
local function mul32(a: number, b: number): number
	local aHi = bit32.rshift(a, 16)
	local aLo = a % 65536
	local bLo = b % 65536
	local lo = aLo * bLo
	local mid = (aHi * bLo + aLo * bit32.rshift(b, 16)) % 65536
	return (lo + mid * 65536) % 4294967296
end

-- splitmix32-style finalizer: adjacent inputs decorrelate completely (avalanche). The previous
-- linear-congruential mix left first stream draws linearly correlated across arithmetic-progression
-- master seeds, which collapsed weighted archetype selection onto a subset of archetypes.
local function mix(master: number, tag: number): number
	local h = (master * 65536 + tag) % 4294967296
	h = mul32(bit32.bxor(h, bit32.rshift(h, 16)) % 4294967296, 0x85ebca6b)
	h = bit32.bxor(h, bit32.rshift(h, 13)) % 4294967296
	h = mul32(h, 0xc2b2ae35)
	h = bit32.bxor(h, bit32.rshift(h, 16)) % 4294967296
	local out = h % 2147483646
	if out <= 0 then out += 2147483646 end
	return out
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

-- splitmix32 generator in pure Luau: bit32 ops are identical in Roblox and the standalone CLI,
-- so streams are bit-for-bit reproducible in both environments with zero Random.new dependency.
-- (Random.new also exhibits first-draw correlation for adjacent seeds; splitmix32 does not.)
local StreamMT = {}
StreamMT.__index = StreamMT

function StreamMT:NextNumber(a: number?, b: number?): number
	self.state = (self.state + 0x9E3779B9) % 4294967296
	local z = self.state
	z = mul32(bit32.bxor(z, bit32.rshift(z, 16)) % 4294967296, 0x85ebca6b)
	z = bit32.bxor(z, bit32.rshift(z, 13)) % 4294967296
	z = mul32(z, 0xc2b2ae35)
	z = bit32.bxor(z, bit32.rshift(z, 16)) % 4294967296
	local u = z / 4294967296
	if a == nil then return u end
	if b == nil then return a * u end
	return a + (b - a) * u
end

function StreamMT:NextInteger(a: number, b: number): number
	return math.floor(self:NextNumber(a, b + 1))
end

-- Random.new-compatible object from any integer seed.
function SeedStream.fromSeed(seed: number): any
	return setmetatable({ state = math.floor(seed) % 4294967296 }, StreamMT)
end

-- Returns a function producing uniform [0,1) draws, seeded per-stream so streams are independent.
function SeedStream.stream(master: number, name: string): () -> number
	local tag = TAGS[name] or 97
	local rng = SeedStream.fromSeed(mix(master, tag))
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
