import struct,re,json
from capstone import *
fw_path="../mouse_00E2_fw.bin"
import fwlib; fw=fwlib.FW(fw_path); d=fw.d; base=fw.base; N=fw.N
md=Cs(CS_ARCH_ARM,CS_MODE_THUMB|CS_MODE_MCLASS); md.detail=True
handlers={0x00:0x5054c,0x02:0x50d98,0x04:0x51590,0x05:0x52fac,0x06:0x5310c,0x07:0x53370,0x0b:0x52248,0x0f:0x52938,0x10:0x56a78,0x15:0x5378c}
bounds=sorted(handlers.values())+[0x568e0]
def span(h):
    nxt=min([s for s in bounds if s>h],default=h+0x700); return h,min(nxt,h+0x800)
def tbl_targets(site,kind,cnt):
    tbl=site+4; t=[]
    for i in range(cnt):
        off=d[fw.fo(tbl)+i] if kind=='tbb' else struct.unpack('<H',d[fw.fo(tbl)+2*i:fw.fo(tbl)+2*i+2])[0]
        t.append(tbl+2*off)
    return t
def analyze(cls,h):
    s,e=span(h); off={}; ids=set(); idregs=set()
    insns=list(md.disasm(d[fw.fo(s):fw.fo(e)],s))
    for idx,ins in enumerate(insns):
        m=ins.mnemonic; ops=[o.strip() for o in ins.op_str.split(',')]
        # id load: ldrb rX,[rY,#7]
        if m.startswith('ldrb') and '#7]' in ins.op_str.replace(' ',''):
            r=ops[0]; off[r]=0; idregs.add(r); continue
        if m in('mov','mov.w','uxtb') and len(ops)==2 and ops[1] in idregs:
            off[ops[0]]=off.get(ops[1],0); idregs.add(ops[0]); continue
        if m in('subs','sub','sub.w') and ops[0] in idregs and ops[-1].startswith('#'):
            try: off[ops[0]]=off.get(ops[0],0)+int(ops[-1][1:],0)
            except: pass
            continue
        if m in('adds','add','add.w') and ops[0] in idregs and ops[-1].startswith('#') and len(ops)==2:
            try: off[ops[0]]=off.get(ops[0],0)-int(ops[-1][1:],0)
            except: pass
            continue
        if m in('cmp','cmp.w') and ops[0] in idregs and ops[-1].startswith('#'):
            try:
                imm=int(ops[-1][1:],0); cand=imm+off.get(ops[0],0)
                if 0<=cand<=0xff: ids.add(cand)
            except: pass
            continue
        if m in('tbb','tbh') and '[pc' in ins.op_str:
            rn='r'+re.search(r'r(\d+)',ins.op_str.split(',')[1]).group(1) if ',' in ins.op_str else None
            b=off.get(rn,0)
            # count from previous cmp on rn
            cnt=0
            for j in range(idx-1,max(0,idx-5),-1):
                pm=insns[j]
                if pm.mnemonic.startswith('cmp') and pm.op_str.split(',')[0].strip()==rn:
                    try: cnt=int(pm.op_str.split('#')[-1],0)+1
                    except: cnt=0
                    break
            if cnt and cnt<0x80:
                tg=tbl_targets(ins.address,ins.mnemonic,cnt)
                from collections import Counter
                default,_=Counter(tg).most_common(1)[0]
                for i,t in enumerate(tg):
                    if t!=default: ids.add(b+i)
            continue
    return sorted(i for i in ids if i<=0xff)
res={}
names={0x00:'device/system',0x02:'buttons+scroll',0x04:'DPI',0x05:'profiles',0x06:'macros',0x07:'power',0x0b:'sensor',0x0f:'lighting',0x10:'class 0x10',0x15:'Hapticore'}
for cls,h in sorted(handlers.items()):
    ids=analyze(cls,h)
    g=[i for i in ids if i>=0x80]; sset=[i for i in ids if i<0x80]
    res[cls]={'set':sset,'get':g}
    print(f"class {cls:#04x} {names[cls]:16}: {len(ids)} cmds | SET {[hex(i) for i in sset]} | GET {[hex(i) for i in g]}")
json.dump({f'{k:#04x}':{'set':[f'{i:#04x}' for i in v['set']],'get':[f'{i:#04x}' for i in v['get']]} for k,v in res.items()},open('/tmp/cmdmatrix.json','w'),indent=1)
