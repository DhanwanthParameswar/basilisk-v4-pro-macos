import os, sys, zlib, gzip, re
root, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
pat = re.compile(rb'Basilisk V4 Pro|basilisk[-_ ]?v4[-_ ]?pro|pid["\']?\s*[:=]\s*(226|0x0?0?e2)\b', re.I)
hits = 0
for dp, _, fs in os.walk(root):
    for f in fs:
        p = os.path.join(dp, f); b = open(p, 'rb').read()
        cands = [b]
        for i in (b.find(b'\x1f\x8b\x08'),):
            if i >= 0:
                try: cands.append(gzip.decompress(b[i:]))
                except Exception:
                    try: cands.append(zlib.decompressobj(16+15).decompress(b[i:]))
                    except Exception: pass
        try:
            import brotli  # optional
            cands.append(brotli.decompress(b))
        except Exception: pass
        for c in cands:
            m = pat.search(c)
            if m:
                hits += 1
                url = re.search(rb'https?://[\x21-\x7e]{8,300}', b)
                name = f'{hits:03d}_{len(c)//1024}k.bin'
                open(os.path.join(out, name), 'wb').write(c)
                print(name, m.group(0)[:40], url.group(0)[:160].decode() if url else '')
                break
print('hits', hits)
