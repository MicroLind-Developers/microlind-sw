#!/usr/bin/env python3
"""Measure UART command latency and cycle attribution on disposable CF images."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root.parent / 'bios/tools'))
from check_rom import read_symbols
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--build', type=Path, default=root / 'build')
p.add_argument('--simulator', type=Path, required=True)
p.add_argument('--engine', choices=['instruction', 'microcycle', 'both'], default='both')
p.add_argument('--samples', type=int, default=3)
p.add_argument('--output', type=Path, help='separate directory for logs and disposable image')
p.add_argument('--scenario', default='*', help='one scenario label, or * for the full suite')
a = p.parse_args()
if not 1 <= a.samples <= 20:
    p.error('samples must be 1..20')
b, sim = a.build.resolve(), a.simulator.resolve(strict=True)
work = a.output.resolve() if a.output else b / 'response-profile'
work.mkdir(parents=True, exist_ok=True)
symbols = {}
for name in ['runtime.sym', 'boot.sym']:
    symbols.update(read_symbols(b / name))
def main_address(path):
    return int(re.search(r'Symbol: _mlos_program_main .* = ([0-9A-F]+)', path.read_text())[1], 16)

symbols['command_program_main'] = main_address(b / 'command.map')
small_commands = ['echo', 'pwd', 'ls', 'cat', 'cp', 'mem']
for name in small_commands:
    path = b / (name + '.map')
    symbols[name + '_program_main'] = main_address(path) if path.exists() else symbols['command_program_main']
(work / 'target_runtime.hpp').write_text('#pragma once\n' +
    ('#define PROFILE_CHUNK_LOADER\n' if 'ir_copy' in symbols else '') + 'namespace target {\n' + ''.join(
    f'constexpr int {k}={v};\n' for k,v in symbols.items()
    if re.fullmatch('[A-Za-z_][A-Za-z_0-9]*', k)) + '}\n')
runner = work / 'response-profile'
subprocess.run(['c++','-std=c++20','-O2','-Wall','-Wextra','-Werror',
    '-I', str(root.parent.parent / 'microlind-sim/include'), '-I', str(work),
    str(root / 'tests/runtime/response_profile.cpp'), str(sim.parent / 'libmicrolind-sim-app.a'),
    str(sim.parent / 'libmicrolind-sim.a'), '-pthread','-o',str(runner)], check=True, timeout=60)
fixture = work / 'response-fixture'
subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Dtime=fixture_time',
    '-Dclock=fixture_clock','-Drand=fixture_rand','-I',str(root.parent/'mlfs/lib/include'),
    str(root/'tests/runtime/response_fixture.c'),str(root.parent/'mlfs/lib/src/mlfs.c'),
    '-o',str(fixture)], check=True, timeout=30)
image = work / 'working.img'
config = (root / 'hardware.cfg').read_text().replace('SECTORS=512',
    'SECTORS=4096\nIMAGE=' + str(image))
(work / 'runtime.cfg').write_text(config)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def instruction_sources(path):
    result = {}
    for line in path.read_text().splitlines():
        m = re.match(r'^([0-9A-F]{4})\s+[0-9A-F]+\s+\(([^)]+)\):[0-9]+', line)
        if m:
            result[int(m[1],16)] = Path(m[2].strip()).name
    return result

sources = {'core': instruction_sources(b/'runtime.lst'), 'rom': instruction_sources(b/'boot.lst')}
report = {'generated_utc':datetime.now(timezone.utc).isoformat(),
    'simulator_build_type':next((line.split('=',1)[1] for line in
        (sim.parent/'CMakeCache.txt').read_text().splitlines()
        if line.startswith('CMAKE_BUILD_TYPE:')), 'unknown'),
    'tool_versions':{tool:subprocess.check_output([tool, '--version'],text=True).splitlines()[0]
        for tool in ['lwasm','cmoc','c++','python3']},
    'profiler_sha256':{str(path.relative_to(root)):sha(path) for path in [
        Path(__file__).resolve(),root/'tests/runtime/response_profile.cpp',
        root/'tests/runtime/response_fixture.c',root/'tests/runtime/runner.cpp',
        root/'tests/runtime/mkimage.c']},
    'hardware_config_sha256':sha(root/'hardware.cfg'),
    'cpu_hz':3000000,'samples':a.samples,'scenario':a.scenario,
    'artifacts_sha256':{name:sha(b/name) for name in ['boot.ihex','mlos.bin','console.img','command.mlx'] +
        [name+'.mlx' for name in small_commands if (b/(name+'.mlx')).exists()]},
    'simulator_libraries_sha256':{name:sha(sim.parent/name) for name in ['libmicrolind-sim.a','libmicrolind-sim-app.a']},
    'runs':[]}
domains = ['core','rom','shell','filesystem','worker','command','init','irq_entry','idle','other']
engines = ['instruction','microcycle'] if a.engine=='both' else [a.engine]
for engine in engines:
    shutil.copyfile(b/'console.img',image)
    subprocess.run([str(fixture),str(image)],check=True)
    raw = work / f'{engine}.jsonl'
    log = work / f'{engine}.log'
    with raw.open('w') as out, log.open('w') as err:
        r = subprocess.run([str(runner),str(b/'boot.ihex'),str(work/'runtime.cfg'),engine,
                            str(a.samples),a.scenario],stdout=out,stderr=err,timeout=1200)
    if r.returncode:
        raise SystemExit(log.read_text())
    for scenario,mode in [('copy','verify-copy'),('redirect','verify-redirect')]:
        if a.scenario in ['*',scenario]:
            subprocess.run([str(fixture),str(image),mode],check=True)
    subprocess.run([sys.executable,str(root.parent/'mlfs/tools/check_image.py'),str(image)],
                   check=True,stdout=subprocess.PIPE,text=True)
    rows = [json.loads(line) for line in raw.read_text().splitlines()]
    trials = [v for v in rows if v['type']=='trial']
    if not trials:
        raise SystemExit('No trials: unknown scenario ' + a.scenario)
    for row in trials:
        buckets = defaultdict(int)
        for key,cycles in row.pop('pc_cycles',[]):
            d,pc = domains[key//65536], key%65536
            unit = sources.get(d,{}).get(pc,d)
            buckets[d+'/'+unit] += cycles
        row['source_cycles']=dict(sorted(buckets.items(),key=lambda p:-p[1]))
        assert sum(row['domains'].values()) == row['cycles']
        assert row['masked_cycles'] <= row['cycles']
    summaries = []
    for label in dict.fromkeys(v['label'] for v in trials):
        group = [v for v in trials if v['label']==label]
        event = lambda name: [v['events'][name]/3000 for v in group if name in v['events']]
        times = [v['cycles']/3000 for v in group]
        phases = {}
        for left,right,name in [('spawn_syscall','image_loaded','image_load'),
                ('image_loaded','command_entry','handoff'),('command_entry','command_main','crt_stdio'),
                ('command_main','command_exit','body_close'),('command_exit','prompt','exit_to_prompt')]:
            values=[(v['events'][right]-v['events'][left])/3000 for v in group
                    if left in v['events'] and right in v['events']]
            if values: phases[name]=statistics.median(values)
        item={'label':label,'samples':len(group),'median_ms':statistics.median(times),
              'min_ms':min(times),'max_ms':max(times),'first_ms':times[0],
              'first_result_ms':statistics.median(event('first_result')) if event('first_result') else None,
              'enter_echo_ms':statistics.median(event('enter_echo')) if event('enter_echo') else None,
              'phases_median_ms':phases}
        summaries.append(item)
        print(engine,label,f"median={item['median_ms']:.3f} ms",f"range={min(times):.3f}..{max(times):.3f}")
    report['runs'].append({'engine':engine,'boot':rows[0],'summaries':summaries,'trials':trials})
    (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['artifacts_sha256']['console.img']==sha(b/'console.img')
print('Saved',work/'results.json')
