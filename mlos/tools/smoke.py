#!/usr/bin/env python3
"""Bounded CLI smoke plus actual target tests in both simulator engines."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'bios/tools'))
from check_rom import read_symbols
from image_formats import image_bytes, read_records

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--simulator', required=True, type=Path)
parser.add_argument('--build', required=True, type=Path)
parser.add_argument('--cxx', default='c++')
args = parser.parse_args()
build = args.build.resolve()
simulator = args.simulator.resolve(strict=True)
rom = build / 'mlos.ihex'
command = [str(simulator), '--6309', '--ihex', '--rom', str(rom), '--config', str(root / 'hardware.cfg')]
result = subprocess.run(command, input='run 100000\nregs\npeek 0xC000 16\npeek 0xF400 6\nexit\n',
                        text=True, capture_output=True, timeout=20)
(build / 'smoke.log').write_text(result.stdout + result.stderr)
assert result.returncode == 0, result.stderr
# Both printable and control-byte CLI forms contain a single 0xNN token.
serial = bytes(int(byte, 16) for byte in re.findall(r'\[SERIAL TX\][^\n]*0x([0-9a-f]{2})', result.stdout))
assert serial == b'MLOS S00-S02 PASS\r\n', result.stdout
assert 'c000: 00 00 00 00 00 00 00 00 a5' in result.stdout, result.stdout
assert 'f400: 03 02 02 01 f0 00' in result.stdout, result.stdout
symbols = {}
for file in ['core.sym', 'rom.sym', 'app.sym']:
    symbols.update(read_symbols(build / file))
header = '#pragma once\nnamespace target {\n'
for key, value in symbols.items():
    if re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', key):
        if value >= 2**31:
            value -= 2**32
        header += f'constexpr int {key} = {value};\n'
header += '}\n'
(build / 'target_symbols.hpp').write_text(header)
sim_root = root.parent.parent / 'microlind-sim'
runner = build / 'target-tests'
subprocess.run([args.cxx, '-std=c++20', '-Wall', '-Wextra', '-Werror', '-O2',
                '-I', str(sim_root / 'include'), '-I', str(build), str(root / 'tests/runner.cpp'),
                str(simulator.parent / 'libmicrolind-sim-app.a'),
                str(simulator.parent / 'libmicrolind-sim.a'), '-pthread', '-o', str(runner)], check=True, timeout=30)
cimage = image_bytes(read_records(build / 'cmoc_client.srec'))
cimage.update(image_bytes(read_records(build / 'cmoc_entry.ihex')))
assert cimage and all(0x400 <= a < 0x3A00 for a in cimage)
craw = build / 'cmoc-app.raw'
craw.write_bytes(bytes(cimage.get(a, 0) for a in range(0x400, max(cimage) + 1)))
result = subprocess.run([str(runner), str(rom), str(root / 'hardware.cfg'), str(craw)], capture_output=True, text=True, timeout=30)
(build / 'contracts.log').write_text(result.stdout + result.stderr)
print(result.stdout, end='')
assert result.returncode == 0, result.stderr
print('CLI serial, target contracts, native registers/maps/stacks: PASS')
