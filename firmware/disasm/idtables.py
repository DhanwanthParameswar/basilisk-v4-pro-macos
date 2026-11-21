import struct,fwlib
from capstone import *
fw=fwlib.FW("../mouse_00E2_fw.bin"); d=fw.d; base=fw.base; N=fw.N
md=Cs(CS_ARCH_ARM,CS_MODE_THUMB|CS_MODE_MCLASS)
def tbb_sites():
    out=[]
    for o in range(0,N-3):
        if d[o]==0xDF and d[o+1]==0xE8 and d[o+3]==0xF0 and (d[o+2]&0xF0) in(0,0x10):
            out.append((base+o,'tbh' if d[o+2]&0x10 else 'tbb'))
    return out
def prev_cmp(addr):
    start=fw.fo(addr)-20; last=None
    for ins in md.disasm(d[start:fw.fo(addr)],base+start):
        if ins.mnemonic in('cmp','cmp.w') and '#' in ins.op_str:
            try:last=int(ins.op_str.split('#')[-1],0)
            except:pass
    return last
def decode(site,kind,n):
    tbl=site+4; out=[]
    for i in range(n):
        off=d[fw.fo(tbl)+i] if kind=='tbb' else struct.unpack('<H',d[fw.fo(tbl)+2*i:fw.fo(tbl)+2*i+2])[0]
        out.append(tbl+2*off)
    return out
SITES=tbb_sites()
handlers={0x00:0x5054c,0x02:0x50d98,0x04:0x51590,0x05:0x52fac,0x06:0x5310c,0x07:0x53370,0x0b:0x52248,0x0f:0x52938,0x10:0x56a78,0x15:0x5378c}
order=sorted(handlers.values())
def endof(h):
    nxt=[x for x in order if x>h]
    return nxt[0] if nxt else h+0x900
names={0x00:'device/system',0x02:'buttons+scroll',0x04:'DPI',0x05:'profiles',0x06:'macros',0x07:'power',0x0b:'sensor',0x0f:'lighting',0x10:'class0x10',0x15:'Hapticore'}
allcmds={}
for cls,h in sorted(handlers.items()):
    e=endof(h)
    insites=[(a,k) for a,k in SITES if h<=a<e]
    best=None
    for a,k in insites:
        n=prev_cmp(a); 
        if n is None or n>80: continue
        tg=decode(a,k,n+1)
        from collections import Counter
        default,dc=Counter(tg).most_common(1)[0]
        impl=[i for i,t in enumerate(tg) if t!=default]
        if best is None or len(impl)>len(best[1]): best=(a,impl,n+1,default)
    if best:
        a,impl,n,default=best
        allcmds[cls]=impl
        print(f"class {cls:#04x} {names[cls]:14} handler {h:#x}: id-table @{a:#x} ({n} entries) -> cmd#s {[hex(i) for i in impl]}")
    else:
        print(f"class {cls:#04x} {names[cls]:14} handler {h:#x}: (cmp-chain, no tbb) -- disasm needed")
import json;json.dump({hex(k):[hex(i) for i in v] for k,v in allcmds.items()},open('/tmp/idtables.json','w'))
