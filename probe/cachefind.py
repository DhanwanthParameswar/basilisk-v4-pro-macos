import os, sys, gzip, re
root, out, pat = sys.argv[1], sys.argv[2], re.compile(sys.argv[3].encode())
os.makedirs(out, exist_ok=True); seen=set()
for dp, _, fs in os.walk(root):
    for f in fs:
        b = open(os.path.join(dp, f), 'rb').read()
        url = re.search(rb'https?://[\x21-\x7e]{8,300}?\.js', b)
        i = b.find(b'\x1f\x8b\x08'); c = b
        if i >= 0:
            try: c = gzip.decompress(b[i:])
            except Exception: pass
        if pat.search(c):
            u = url.group(0).decode() if url else f
            name = u.rsplit('/', 1)[-1]
            if name in seen: continue
            seen.add(name); open(os.path.join(out, name), 'wb').write(c)
            print(f'{len(c)//1024:6d}k  {u}')
