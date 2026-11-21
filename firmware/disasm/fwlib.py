"""Basilisk V4 Pro nRF54 firmware analysis helpers."""
import struct,re
from capstone import *
class FW:
    def __init__(self,path,base=0x22000):
        self.d=open(path,'rb').read(); self.N=len(self.d); self.base=base
        self.md=Cs(CS_ARCH_ARM,CS_MODE_THUMB|CS_MODE_MCLASS); self.md.detail=True
    def fo(self,a): return a-self.base
    def w(self,a):
        f=a-self.base; return struct.unpack('<I',self.d[f:f+4])[0]
    def str_at(self,a):
        f=a-self.base
        if not(0<=f<self.N): return None
        m=re.match(rb'[\x20-\x7e]{3,}',self.d[f:f+120])
        return m.group().decode() if m else None
    def strings(self):
        out={}
        for m in re.finditer(rb'[\x20-\x7e]{5,}',self.d):
            out[self.base+m.start()]=m.group().decode()
        return out
    def xrefs_to(self,target):
        """code offsets whose pc-relative ldr loads a word == target"""
        res=[]
        a=self.base
        for ins in self.md.disasm(self.d,self.base):
            if ins.mnemonic.startswith('ldr') and '[pc' in ins.op_str:
                lit=(ins.address+4)&~3
                try: val=self.w(lit+int(ins.op_str.split('#')[-1].rstrip(']'),0))
                except: continue
                if val==target: res.append(ins.address)
        return res
    def func_start(self,addr,back=0x400):
        """nearest preceding push{...,lr} (0xb5xx) 2-aligned"""
        f=self.fo(addr)
        for o in range(f& ~1, max(0,f-back),-2):
            hw=struct.unpack('<H',self.d[o:o+2])[0]
            if 0xb500<=hw<=0xb5ff: return self.base+o
        return None
    def disasm(self,addr,n=40):
        out=[]
        for ins in self.md.disasm(self.d[self.fo(addr):self.fo(addr)+n*2],addr):
            out.append((ins.address,ins.mnemonic,ins.op_str)); 
            if len(out)>=n: break
        return out
