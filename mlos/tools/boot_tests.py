#!/usr/bin/env python3
import argparse,subprocess,struct,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--simulator',type=Path,required=True);a=p.parse_args();b=a.build.resolve();sim=a.simulator.resolve()
sys.path.insert(0,str(root.parent/'bios/tools'));from check_rom import read_symbols
symbols={}
for f in ['runtime.sym','boot.sym']:symbols.update(read_symbols(b/f))
import re
(b/'target_runtime.hpp').write_text('#pragma once\nnamespace target {\n'+''.join(f'constexpr int {k}={v};\n' for k,v in symbols.items() if re.fullmatch('[A-Za-z_][A-Za-z_0-9]*',k))+'}\n')
base=bytearray((b/'diagnostic.img').read_bytes());u32=lambda off:int.from_bytes(base[off:off+4],'big');part=u32(9);sb=part*512;directory=(part+u32(sb+21))*512;kernel=(part+u32(directory+64))*512
cases=[]
def changed(name,offset,data):
    image=bytearray(base);image[offset:offset+len(data)]=data;cases.append((name,image))
changed('mlpt-version',4,b'\x02');changed('partition-range',9,b'\xff'*4);changed('superblock-checksum',sb+45,b'\x01\x02\x03\x04');changed('missing-kernel',directory,b'\0');changed('extent-range',directory+64,b'\xff'*4);changed('short-header',directory+2,struct.pack('>I',19));changed('kernel-magic',kernel,b'FAIL');changed('kernel-version',kernel+4,b'\0\x02');changed('kernel-oversize',kernel+12,b'\x40\x01');changed('entry-outside',kernel+10,b'\xff\xff');changed('kernel-checksum',kernel+16,b'\xff'*4);changed('kernel-corrupt',kernel+20,b'\xff');changed('length-mismatch',directory+2,struct.pack('>I',21))
configs=[]
for name,image in cases:
    target=b/f'reject-{name}.img';target.write_bytes(image);cfg=b/f'reject-{name}.cfg';cfg.write_text((root/'hardware.cfg').read_text().replace('SECTORS=512',f'SECTORS=4096\nIMAGE={target}'));configs.append(str(cfg))
subprocess.run(['c++','-std=c++20','-O2','-Wall','-Wextra','-Werror','-I',str(root.parent.parent/'microlind-sim/include'),'-I',str(b),str(root/'tests/runtime/boot.cpp'),str(sim.parent/'libmicrolind-sim-app.a'),str(sim.parent/'libmicrolind-sim.a'),'-pthread','-o',str(b/'boot-tests')],check=True,timeout=30)
subprocess.run([str(b/'boot-tests'),str(b/'boot.ihex'),*configs],check=True,timeout=60)
