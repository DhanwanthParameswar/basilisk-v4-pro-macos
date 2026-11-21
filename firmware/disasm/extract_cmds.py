import struct,re,sys
from capstone import *
import fwlib
fw=fwlib.FW("../mouse_00E2_fw.bin"); d=fw.d; N=fw.N; base=fw.base
md=Cs(CS_ARCH_ARM,CS_MODE_THUMB|CS_MODE_MCLASS)
# find function starts: push{...,lr} encodings  B5xx (T1) or E92D..(T2 push.w with lr)
starts=set()
for o in range(0,N-1,2):
    hw=struct.unpack('<H',d[o:o+2])[0]
    if 0xb500<=hw<=0xb5ff: starts.add(o)
    if hw==0xe92d:
        hw2=struct.unpack('<H',d[o+2:o+4])[0]
        if hw2&0x4000: starts.add(o)
starts=sorted(starts)
# for each function, disasm until pop/bx lr or next start; detect status-5 default + cmp immediates on a byte
def func_body(o):
    end=N
    nxt=[s for s in starts if s>o]
    if nxt: end=min(end,nxt[0]+0)  # until next start
    end=min(end,o+0x600)
    return d[o:end]
results=[]
for o in starts:
    code=func_body(o)
    cmps=[]; has_ns=False; byteload=False
    for ins in md.disasm(code,base+o):
        if ins.mnemonic=='ldrb': byteload=True
        if ins.mnemonic in('cmp','cmp.w') and '#' in ins.op_str:
            try:
                imm=int(ins.op_str.split('#')[-1],0)
                if 0<=imm<=0xff: cmps.append(imm)
            except: pass
        # status-5 not-supported: strb with #5 then [rX,#7]  -> detect movs r?,#5 ; strb r?,[?,#7]
        if ins.mnemonic in('strb','strb.w') and ',#7]' in ins.op_str.replace(' ',''):
            has_ns=True
        if ins.mnemonic in('pop','pop.w','bx') and len(list(md.disasm(code[ins.address-base-o:ins.address-base-o+2],0)))>=0:
            pass
    idcmps=[c for c in cmps if c>=0x80]   # GET ids are 0x80+
    if has_ns and byteload and len(set(idcmps))>=2:
        results.append((base+o,sorted(set(idcmps))))
print(f"candidate class-dispatchers: {len(results)}")
allids=set()
for fa,ids in results:
    allids|=set(ids)
    print(f"  func {fa:#x}: GET ids "+' '.join(f'{i:#x}' for i in ids))
print(f"\nunion of GET ids seen in dispatchers ({len(allids)}): "+' '.join(f'{i:#02x}' for i in sorted(allids)))
