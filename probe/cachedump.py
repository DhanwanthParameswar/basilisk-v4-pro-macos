import os, sys, gzip, re
root, out, prefix = sys.argv[1], sys.argv[2], sys.argv[3].encode()
os.makedirs(out, exist_ok=True)
for dp, _, fs in os.walk(root):
    for f in fs:
        b = open(os.path.join(dp, f), 'rb').read()
        m = re.search(re.escape(prefix) + rb'([\x21-\x7e]+?\.(js|json))', b)
        if not m: continue
        i = b.find(b'\x1f\x8b\x08')
        if i < 0: continue
        try: c = gzip.decompress(b[i:])
        except Exception:
            import zlib
            try: c = zlib.decompressobj(31).decompress(b[i:])
            except Exception: continue
        name = m.group(1).decode().split('?')[0]
        p = os.path.join(out, name)
        if not os.path.exists(p) or os.path.getsize(p) < len(c): open(p, 'wb').write(c)
for n in sorted(os.listdir(out)): print(f'{os.path.getsize(os.path.join(out,n))//1024:6d}k {n}')
