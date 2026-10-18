#!/usr/bin/env python3
import argparse,re,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'bios/tools'))
from check_rom import read_symbols
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--simulator',type=Path,required=True);a=p.parse_args();b=a.build.resolve();sim=a.simulator.resolve()
cfg=(root/'hardware.cfg').read_text().replace('SECTORS=512','SECTORS=4096\nIMAGE='+str(b/'diagnostic.img'))
(b/'diagnostic.cfg').write_text(cfg)
symbols={}
for f in ['runtime.sym','boot.sym']:symbols.update(read_symbols(b/f))
(b/'target_runtime.hpp').write_text('#pragma once\nnamespace target {\n'+''.join(f'constexpr int {k}={v};\n' for k,v in symbols.items() if re.fullmatch('[A-Za-z_][A-Za-z_0-9]*',k))+'}\n')
subprocess.run(['c++','-std=c++20','-O2','-Wall','-Wextra','-Werror','-I',str(root.parent.parent/'microlind-sim/include'),'-I',str(b),str(root/'tests/runtime/runner.cpp'),str(sim.parent/'libmicrolind-sim-app.a'),str(sim.parent/'libmicrolind-sim.a'),'-pthread','-o',str(b/'runtime-tests')],check=True,timeout=30)
r=subprocess.run([str(b/'runtime-tests'),str(b/'boot.ihex'),str(b/'diagnostic.cfg')],text=True,capture_output=True,timeout=90)
(b/'runtime-tests.log').write_text(r.stdout+r.stderr);print(r.stdout,end='');print(r.stderr,end='',file=sys.stderr)
if r.returncode:raise SystemExit(r.returncode)
