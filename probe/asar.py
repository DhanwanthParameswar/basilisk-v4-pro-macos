import json, struct, sys, os
src, dst = sys.argv[1], sys.argv[2]
f = open(src, 'rb'); head = f.read(16)
size = struct.unpack('<I', head[4:8])[0]; jlen = struct.unpack('<I', head[12:16])[0]
hdr = json.loads(f.read(jlen)); base = 8 + size
n = 0
def walk(node, path):
    global n
    for name, e in node.get('files', {}).items():
        p = os.path.join(path, name)
        if 'files' in e: walk(e, p)
        elif e.get('unpacked') or 'offset' not in e: continue
        else:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            f.seek(base + int(e['offset'])); open(p, 'wb').write(f.read(e['size'])); n += 1
walk(hdr, dst); print(n, 'files')
