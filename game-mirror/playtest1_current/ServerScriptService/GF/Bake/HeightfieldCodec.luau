--!strict
-- HeightfieldCodec: decodes base85+delta-packed heightfield chunks into a buffer-backed
-- sampler. Pure arithmetic, no compression library needed. Used offline by the terrain
-- bake (full-res) and at runtime by battlefield analytics (half-res).
-- Format contract with gf-geo/export_modules.py: row-major, col0 absolute uint16LE,
-- then signed byte deltas; escape 127 = followed by absolute uint16LE.

local HeightfieldCodec = {}

local B85 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~"
local REV: { [string]: number } = {}
for i = 1, #B85 do
	REV[string.sub(B85, i, i)] = i - 1
end

local function b85decode(s: string, rawlen: number): buffer
	local buf = buffer.create(rawlen)
	local pos = 0
	local i = 1
	local n = #s
	while i + 4 <= n and pos + 4 <= rawlen do
		local v = REV[string.sub(s, i, i)] or 0
		v = v * 85 + (REV[string.sub(s, i + 1, i + 1)] or 0)
		v = v * 85 + (REV[string.sub(s, i + 2, i + 2)] or 0)
		v = v * 85 + (REV[string.sub(s, i + 3, i + 3)] or 0)
		v = v * 85 + (REV[string.sub(s, i + 4, i + 4)] or 0)
		-- big-endian 4 bytes
		buffer.writeu8(buf, pos, math.floor(v / 16777216) % 256)
		buffer.writeu8(buf, pos + 1, math.floor(v / 65536) % 256)
		buffer.writeu8(buf, pos + 2, math.floor(v / 256) % 256)
		buffer.writeu8(buf, pos + 3, v % 256)
		pos += 4
		i += 5
	end
	return buf
end

export type Heightfield = {
	n: number,
	base: number,
	quant: number,
	heights: buffer, -- uint16 quantized units, row-major n*n
	sample: (x: number, z: number) -> number,
	raw: (row: number, col: number) -> number,
}

-- chunks: array of module-returned strings concatenated in order; meta from exporter json.
function HeightfieldCodec.decode(data: string, n: number, base: number, quant: number, rawlen: number): Heightfield
	local packed = b85decode(data, rawlen)
	-- reconstruct quantized grid into uint16 buffer
	local grid = buffer.create(n * n * 2)
	local gp = 0
	local pp = 0
	for r = 0, n - 1 do
		local prev = 0
		for c = 0, n - 1 do
			local v
			if c == 0 then
				v = buffer.readu8(packed, pp) + buffer.readu8(packed, pp + 1) * 256
				pp += 2
			else
				local b = buffer.readu8(packed, pp)
				pp += 1
				if b == 127 then
					v = buffer.readu8(packed, pp) + buffer.readu8(packed, pp + 1) * 256
					pp += 2
				else
					local d = b < 128 and b or b - 256
					v = prev + d
				end
			end
			buffer.writeu16(grid, gp, v)
			gp += 2
			prev = v
		end
	end

	local hf: any = {
		n = n,
		base = base,
		quant = quant,
		heights = grid,
	}
	function hf.raw(row: number, col: number): number
		local idx = (row * n + col) * 2
		return base + buffer.readu16(grid, idx) * quant
	end
	-- sample in grid-index space: x,z are fractional grid coordinates 0..n-1, bilinear
	function hf.sample(gx: number, gz: number): number
		local x0 = math.clamp(math.floor(gx), 0, n - 2)
		local z0 = math.clamp(math.floor(gz), 0, n - 2)
		local fx = math.clamp(gx - x0, 0, 1)
		local fz = math.clamp(gz - z0, 0, 1)
		local function rv(rr: number, cc: number): number
			return base + buffer.readu16(grid, (rr * n + cc) * 2) * quant
		end
		local h00 = rv(z0, x0)
		local h10 = rv(z0, x0 + 1)
		local h01 = rv(z0 + 1, x0)
		local h11 = rv(z0 + 1, x0 + 1)
		return h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz
	end
	return hf
end

return HeightfieldCodec
