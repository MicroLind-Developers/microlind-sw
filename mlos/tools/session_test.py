#!/usr/bin/env python3
"""Boot the generated GUI session using its real config/ROM/CF dependencies."""
import argparse
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--build', type=Path, required=True)
p.add_argument('--simulator', type=Path, required=True)
a = p.parse_args()
b = a.build.resolve()
sim = a.simulator.resolve(strict=True)
work = b / 'session-test'
work.mkdir(exist_ok=True)
for name in ['mlos.session', 'boot.ihex', 'console.img']:
    shutil.copyfile(b / name, work / name)
config = (b / 'runtime.cfg').read_text()
config = '\n'.join('IMAGE=' + str(work / 'console.img') if line.startswith('IMAGE=')
                   else line for line in config.splitlines()) + '\n'
(work / 'runtime.cfg').write_text(config)
runner = work / 'session-boot'
subprocess.run(['c++', '-std=c++20', '-O2', '-Wall', '-Wextra', '-Werror',
    '-I', str(root.parent.parent / 'microlind-sim/include'), str(root / 'tests/runtime/session_boot.cpp'),
    str(sim.parent / 'libmicrolind-sim-app.a'), str(sim.parent / 'libmicrolind-sim.a'),
    '-pthread', '-o', str(runner)], check=True, timeout=45)
r = subprocess.run([str(runner), str(work / 'mlos.session')],
                   text=True, capture_output=True, timeout=180)
(b / 'session-test.log').write_text(r.stdout + r.stderr)
print(r.stdout, end='')
if r.returncode:
    raise SystemExit(r.stderr or r.returncode)
