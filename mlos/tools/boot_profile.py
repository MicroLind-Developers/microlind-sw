#!/usr/bin/env python3
"""Observe reset-to-prompt timings on a disposable copy of the installed CF."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root.parent / 'bios/tools'))
from check_rom import read_symbols

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--build', type=Path, default=root / 'build')
p.add_argument('--simulator', type=Path, required=True)
p.add_argument('--engine', choices=['both', 'instruction', 'microcycle'], default='both')
a = p.parse_args()
b = a.build.resolve()
sim = a.simulator.resolve(strict=True)
work = b / 'boot-profile'
work.mkdir(exist_ok=True)
symbols = {}
for name in ['runtime.sym', 'boot.sym']:
    symbols.update(read_symbols(b / name))
worker = read_symbols(b / 'fs0.sym')
for name in ['FS_MOUNT', 'volume_validate']:
    symbols['worker_' + name] = worker[name]
(work / 'target_runtime.hpp').write_text('#pragma once\nnamespace target {\n' + ''.join(
    f'constexpr int {k}={v};\n' for k, v in symbols.items()
    if re.fullmatch('[A-Za-z_][A-Za-z_0-9]*', k)) + '}\n')
image = work / 'console.img'
config = (root / 'hardware.cfg').read_text().replace(
    'SECTORS=512', 'SECTORS=4096\nIMAGE=' + str(image))
(work / 'runtime.cfg').write_text(config)
runner = work / 'boot-profile'
subprocess.run(['c++', '-std=c++20', '-O2', '-Wall', '-Wextra', '-Werror',
    '-I', str(root.parent.parent / 'microlind-sim/include'), '-I', str(work),
    str(root / 'tests/runtime/boot_profile.cpp'), str(sim.parent / 'libmicrolind-sim-app.a'),
    str(sim.parent / 'libmicrolind-sim.a'), '-pthread', '-o', str(runner)], check=True, timeout=45)
report = {'artifacts_sha256': {name: hashlib.sha256((b / name).read_bytes()).hexdigest()
          for name in ['boot.ihex', 'mlos.bin', 'console.img']},
          'simulator_sha256': hashlib.sha256(sim.read_bytes()).hexdigest(), 'runs': []}
engines = ['instruction', 'microcycle'] if a.engine == 'both' else [a.engine]
for engine in engines:
    shutil.copyfile(b / 'console.img', image)
    r = subprocess.run([str(runner), str(b / 'boot.ihex'), str(work / 'runtime.cfg'), engine],
                       capture_output=True, text=True, timeout=180)
    if r.returncode:
        raise SystemExit(r.stderr or r.stdout)
    run = json.loads(r.stdout)
    events = {event['name']: event for event in run['events']}
    for name in ['reset_entry', 'power_led_on', 'first_console_byte', 'common_clear_start', 'common_clear_complete',
                 'cf_identify_start', 'partition_validation_start', 'kernel_entry',
                 'init_first_instruction', 'filesystem_first_instruction',
                 'worker_validation_start', 'worker_listener_ready', 'root_volume_online',
                 'filesystem_listener_ready', 'shell_first_instruction', 'prompt_complete']:
        if name not in events:
            raise SystemExit(f'{engine}: missing milestone {name}')
    clear_steps = (events['common_clear_complete']['instruction_steps'] -
                   events['common_clear_start']['instruction_steps'])
    if clear_steps != 8192 * 3:
        raise SystemExit(f'{engine}: unexpected common-clear loop: {clear_steps} steps')
    if not (events['power_led_on']['cycles'] < events['first_console_byte']['cycles'] <
            events['common_clear_start']['cycles']):
        raise SystemExit(f'{engine}: expected LED and serial feedback before RAM clear')
    report['runs'].append(run)
    print(engine + ':')
    previous = 0
    for event in run['events']:
        delta = event['cycles'] - previous
        previous = event['cycles']
        print(f"  {event['name']:34s} {event['cycles']:11,d} cycles total, "
              f"+{delta / run['cpu_hz'] * 1000:10.3f} ms, "
              f"{event['instruction_steps']:9,d} instruction steps total")
(work / 'timings.json').write_text(json.dumps(report, indent=2) + '\n')
print('Saved', work / 'timings.json')
