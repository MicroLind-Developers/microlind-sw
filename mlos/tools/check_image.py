#!/usr/bin/env python3
"""Enforce physical/logical budgets and ROM overlay/vector placement."""
import argparse
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'bios/tools'))
from image_formats import image_bytes, read_records
from check_rom import read_symbols

parser = argparse.ArgumentParser()
parser.add_argument('--build', type=Path, required=True)
args = parser.parse_args()
build = args.build
image = image_bytes(read_records(build / 'mlos.ihex'))
assert image and all(0xE000 <= a < 0xF400 or 0xF800 <= a <= 0xFFFF for a in image), 'ROM overlaps I/O/RAM'
assert all(image.get(a) == 0x7E for a in range(0xF800, 0xF812, 3)), 'ROM ABI entries must be absolute JMPs'
assert all(a in image for a in range(0xFFF0, 0x10000)), 'missing vectors'
for a in range(0xFFF0, 0x10000, 2):
    target = (image[a] << 8) | image[a + 1]
    assert target in image, f'vector {a:04X} points outside ROM'
assert (build / 'core.raw').stat().st_size <= 16384
assert (build / 'app.raw').stat().st_size <= 0x3600
core = read_symbols(build / 'core.sym')
assert core['COMMON_USED_END'] - 0xC000 <= 8192
budget = {
    'core_bytes': (build / 'core.raw').stat().st_size,
    'rom_populated_bytes': len(image),
    'rom_address_budget': 8192,
    'io_overlay_bytes': 1024,
    'usable_rom_bytes': 7168,
    'common_address_reserved_bytes': core['COMMON_USED_END'] - 0xC000,
    'common_exposed_bytes': 8192,
    'common_physical_reserved_bytes': 16384,
    'installed_frames': 32, 'reserved_frames': 3, 'admissible_frames': 29,
}
import json
(build / 'budget.json').write_text(json.dumps(budget, indent=2) + '\n')
print('MLOS budgets:', ', '.join(f'{k}={v}' for k,v in budget.items()))

rom_symbols = read_symbols(build / 'rom.sym')
map_lines = [
    'MLOS S00-S02 addressed map (hex, inclusive ranges)',
    f"core 0000-{core['CORE_END']-1:04X} in physical frame 0",
    'application 0000-BFFF, three 16 KiB windows; maps and roles are recorded',
    'common C000-DFFF, lower 8 KiB of reserved physical frame 1',
    'C000-C01F entry status and bootstrap scratch',
    'C020-C09F four 32-byte nested-entry records',
    'C100-C109 current PID/map/roles/admission counters',
    'C200-C2FF 32 frame records (8 bytes each)',
    'C300-C3FF 32 handle records (8 bytes each)',
    'C400-C40F copied parameter block',
    'C410-C50F copied payload snapshot',
    'C510-C541 transaction list/scratch/result',
    'C800-C801 kernel stack guard',
    'C802-CFFF 2046-byte kernel stack',
    'D000-D001 emergency stack guard',
    'D002-D1FF 510-byte emergency stack',
    'D200-DFFF unassigned (3584 bytes)',
    f"ROM E000-{rom_symbols['ROM_LOWER_END']-1:04X} entry/backend and embedded test payloads",
    'F400-F7FF I/O overlay (1024 bytes, excluded from ROM)',
    'F800-F811 fixed ROM development bridge slots (six absolute JMPs)',
    'FFF0-FFFF native CPU vectors (16 bytes)',
]
(build / 'maps.txt').write_text('\n'.join(map_lines) + '\n')
