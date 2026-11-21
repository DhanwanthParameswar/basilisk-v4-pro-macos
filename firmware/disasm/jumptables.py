import struct,re
from capstone import *
import fwlib
fw=fwlib.FW("../mouse_00E2_fw.bin"); d=fw.d; base=fw.base; N=fw.N
md=Cs(CS_ARCH_ARM,CS_MODE_THUMB|CS_MODE_MCLASS); md.detail=True
def find_tbb():
    out=[]
    for o in range(0,N-3):
        if d[o]==0xDF and d[o+1]==0xE8 and d[o+3]==0xF0 and (d[o+2]&0xF0) in (0x00,0x10):
            kind='tbh' if (d[o+2]&0x10) else 'tbb'
            out.append((base+o,kind,d[o+2]&0x0f))
    return out
def prev_cmp(addr):
    # disasm a window ending at addr, return last cmp #imm
    start=fw.fo(addr)-24
    last=None
    for ins in md.disasm(d[start:fw.fo(addr)],base+start):
        if ins.mnemonic in('cmp','cmp.w') and '#' in ins.op_str:
            try: last=int(ins.op_str.split('#')[-1],0)
            except: pass
    return last
tbs=find_tbb()
print(f"found {len(tbs)} tbb/tbh sites")
disp=[]
for addr,kind,rn in tbs:
    cnt=prev_cmp(addr)
    tbl=addr+4
    n=(cnt+1) if cnt is not None and cnt<64 else 24
    tgts=[]
    for i in range(n):
        if kind=='tbb': off=d[fw.fo(tbl)+i]
        else: off=struct.unpack('<H',d[fw.fo(tbl)+2*i:fw.fo(tbl)+2*i+2])[0]
        tgts.append(tbl+2*off)
    # dispatcher if some target writes #5 to [x,#7] (status NOT_SUPPORTED) -> check first few targets
    uniq=sorted(set(tgts))
    # heuristic: a default target shared by many entries
    from collections import Counter
    c=Counter(tgts); default,dcount=c.most_common(1)[0]
    is_disp=dcount>=2 and fw.str_at(default) is None
    disp.append((addr,kind,n,default,dcount,tgts))
# print likely command dispatchers: count<=0x16 and a shared default
print("\n=== candidate COMMAND dispatchers (<=22 entries, shared default) ===")
for addr,kind,n,default,dcount,tgts in disp:
    if n<=0x16 and dcount>=2:
        impl=[i for i,t in enumerate(tgts) if t!=default]
        # show class-ish: indices implemented
        print(f"{addr:#x} {kind} n={n} default={default:#x}(x{dcount}) implemented_idx={[hex(i) for i in impl]}")
