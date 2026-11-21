import struct,fwlib
from capstone import *
fw=fwlib.FW("../mouse_00E2_fw.bin"); d=fw.d; base=fw.base; N=fw.N
md=Cs(CS_ARCH_ARM,CS_MODE_THUMB|CS_MODE_MCLASS)
def sites():
    o=[]
    for i in range(0,N-3):
        if d[i]==0xDF and d[i+1]==0xE8 and d[i+3]==0xF0 and (d[i+2]&0xF0)in(0,0x10):
            o.append((base+i,'tbh' if d[i+2]&0x10 else 'tbb'))
    return o
ALL=sites()
def analyze_tbb(site,kind):
    # disasm backwards window to find subs #imm (base) and cmp #imm (count-1)
    start=fw.fo(site)-24
    sub=0; cnt=None
    for ins in md.disasm(d[start:fw.fo(site)],base+start):
        if ins.mnemonic in('subs','sub','sub.w') and '#' in ins.op_str:
            try: sub=int(ins.op_str.split('#')[-1],0)
            except: pass
        if ins.mnemonic in('cmp','cmp.w') and '#' in ins.op_str:
            try: cnt=int(ins.op_str.split('#')[-1],0)
            except: pass
    if cnt is None or cnt>0x7f: return None
    tbl=site+4; tg=[]
    for i in range(cnt+1):
        off=d[fw.fo(tbl)+i] if kind=='tbb' else struct.unpack('<H',d[fw.fo(tbl)+2*i:fw.fo(tbl)+2*i+2])[0]
        tg.append(tbl+2*off)
    from collections import Counter
    default,dc=Counter(tg).most_common(1)[0]
    impl=[sub+i for i,t in enumerate(tg) if t!=default]
    return (sub,impl,default)
handlers={0x00:0x5054c,0x02:0x50d98,0x04:0x51590,0x05:0x52fac,0x06:0x5310c,0x07:0x53370,0x0b:0x52248,0x0f:0x52938,0x10:0x56a78,0x15:0x5378c}
starts=sorted(handlers.values())+[0x568e0]  # bound
names={0x00:'device',0x02:'buttons',0x04:'DPI',0x05:'profiles',0x06:'macros',0x07:'power',0x0b:'sensor',0x0f:'lighting',0x10:'cls10',0x15:'hapti'}
out={}
for cls,h in sorted(handlers.items()):
    nxt=min([s for s in starts if s>h],default=h+0x600)
    ids=set()
    for a,k in ALL:
        if h<=a<nxt:
            r=analyze_tbb(a,k)
            if r: ids|=set(r[1])
    out[cls]=sorted(ids)
    # split get/set
    g=sorted(i for i in ids if i>=0x80); s=sorted(i for i in ids if i<0x80)
    print(f"class {cls:#04x} {names[cls]:9}: SET ids {[hex(i) for i in s]}")
    print(f"               GET ids {[hex(i) for i in g]}")
import json;json.dump({hex(k):[hex(i) for i in v] for k,v in out.items()},open('/tmp/cmds.json','w'))
