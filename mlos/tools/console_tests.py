#!/usr/bin/env python3
import argparse,re,subprocess,sys,shutil,struct
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'bios/tools'))
from check_rom import read_symbols
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--simulator',type=Path,required=True);p.add_argument('--engine',choices=['both','instruction','microcycle'],default='both');a=p.parse_args();b=a.build.resolve();sim=a.simulator.resolve()
shutil.copyfile(b/'console.img',b/'console-test-base.img')
shutil.copyfile(b/'console-test-base.img',b/'console-test.img')
(b/'seed.txt').write_text('second drive\r\n')
subprocess.run([str(b/'mkimage'),str(b/'second-base.img'),'seed',str(b/'seed.txt')],check=True)
shutil.copyfile(b/'second-base.img',b/'second-test.img')
dirty=bytearray((b/'second-base.img').read_bytes())
sb=int.from_bytes(dirty[9:13],'big')*512
dirty[sb+8]=1
dirty[sb+45:sb+49]=bytes(4)
struct.pack_into('>I',dirty,sb+45,sum(dirty[sb:sb+512]))
(b/'second-test.img.dirty').write_bytes(dirty)
cfg=(root/'hardware.cfg').read_text().replace('SECTORS=512','SECTORS=4096\nIMAGE='+str(b/'console-test.img'))
cfg+='\n[CF2]\nIO_START_ADDRESS=0xF640\nIO_END_ADDRESS=0xF647\nSECTORS=4096\nIMAGE='+str(b/'second-test.img')+'\nREAD_ONLY=false\n'
(b/'console.cfg').write_text(cfg)
symbols={}
for f in ['runtime.sym','boot.sym']:symbols.update(read_symbols(b/f))
(b/'target_runtime.hpp').write_text('#pragma once\nnamespace target {\n'+''.join(f'constexpr int {k}={v};\n' for k,v in symbols.items() if re.fullmatch('[A-Za-z_][A-Za-z_0-9]*',k))+'}\n')
subprocess.run(['c++','-std=c++20','-O2','-Wall','-Wextra','-Werror','-I',str(root.parent.parent/'microlind-sim/include'),'-I',str(b),str(root/'tests/runtime/console.cpp'),str(sim.parent/'libmicrolind-sim-app.a'),str(sim.parent/'libmicrolind-sim.a'),'-pthread','-o',str(b/'console-tests')],check=True,timeout=30)
r=subprocess.run([str(b/'console-tests'),str(b/'boot.ihex'),str(b/'console.cfg'),str(b/'console-test-base.img'),str(b/'second-base.img'),a.engine],text=True,capture_output=True,timeout=300)
(b/'console-tests.log').write_text(r.stdout+r.stderr);print(r.stdout,end='');print(r.stderr,end='',file=sys.stderr)
if r.returncode:raise SystemExit(r.returncode)
