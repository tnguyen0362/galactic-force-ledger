# Export heightfield as deployable Luau data modules.
# Format: row-delta byte packing (no zlib needed in Luau - decode is plain arithmetic).
# - heights quantized to 0.25 stud, offset to base 0
# - first column absolute (2 bytes LE), then row deltas as signed bytes
# - delta overflow (>+-120 units) uses escape marker 127 followed by 2-byte absolute
# Output: N chunk modules returning base85-ish strings + a decoder contract.
# We use a custom 91-char alphabet safe for Lua long strings (no backslash/quote/bracket issues
# since we emit as double-quoted strings with escaping of only " and \).
import numpy as np
import zlib, base64, os

def encode_delta(grid, quant=0.25):
    n = grid.shape[0]
    q = np.round((grid - grid.min()) / quant).astype(np.int32)
    out = bytearray()
    for r in range(n):
        prev = 0
        for c in range(n):
            v = int(q[r, c])
            if c == 0:
                out += bytes([v & 0xFF, (v >> 8) & 0xFF])
            else:
                d = v - prev
                if -120 <= d <= 120:
                    out.append((d + 256) % 256 if d < 0 else d)
                else:
                    out.append(127)  # escape: absolute follows
                    out += bytes([v & 0xFF, (v >> 8) & 0xFF])
            prev = v
    return bytes(out), float(grid.min()), quant

def emit(grid, outdir, prefix, chunk_size=55000):
    raw, base, quant = encode_delta(grid)
    pad = (-len(raw)) % 4
    raw_padded = raw + bytes(pad)
    comp = base64.b85encode(raw_padded).decode('ascii')
    print(f"{prefix}: grid {grid.shape}, raw {len(raw)} bytes, b85 {len(comp)} chars")
    os.makedirs(outdir, exist_ok=True)
    nchunks = (len(comp) + chunk_size - 1) // chunk_size
    files = []
    for i in range(nchunks):
        chunk = comp[i*chunk_size:(i+1)*chunk_size]
        # escape for lua double-quoted string: only backslash and quote need escaping
        chunk_lua = chunk.replace(chr(92), chr(92)*2).replace(chr(34), chr(92)+chr(34))
        src = f'-- heightfield data chunk {i+1}/{nchunks} (generated - do not edit)\nreturn "{chunk_lua}"\n'
        fn = os.path.join(outdir, f'{prefix}_d{i:02d}.luau')
        open(fn, 'w', encoding='ascii').write(src)
        files.append(fn)
    meta = dict(chunks=nchunks, n=int(grid.shape[0]), base=float(base), quant=quant,
                rawlen=len(raw))
    import json
    json.dump(meta, open(os.path.join(outdir, f'{prefix}_meta.json'), 'w'))
    print(f"emitted {nchunks} chunks to {outdir}")
    return meta

if __name__ == '__main__':
    grid = np.load(r'C:\Users\tnguy\gf-geo\foundation_v1.npy')
    # full-res for the bake (temporary deploy)
    emit(grid, r'C:\Users\tnguy\gf-geo\out_full', 'bfh')
    # half-res for runtime analytics (permanent ship)
    half = grid[::2, ::2]
    emit(half, r'C:\Users\tnguy\gf-geo\out_half', 'bfa')
