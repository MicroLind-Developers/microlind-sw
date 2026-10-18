#!/usr/bin/env python3
"""Enforce the runtime's addressed ROM/core/common budgets and record artifacts."""
import argparse,json,sys,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'bios/tools'))
from image_formats import image_bytes,read_records
from check_rom import read_symbols
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);a=p.parse_args();b=a.build
symbols=read_symbols(b/'runtime.sym');rom=image_bytes(read_records(b/'boot.ihex'))
assert symbols['CORE_END']<=symbols['HANDLE_TABLE']
assert symbols['HANDLE_TABLE']+symbols['HANDLE_COUNT']*8<=symbols['CHANNEL_TABLE']
assert symbols['CHANNEL_TABLE']+symbols['CHANNEL_COUNT']*symbols['CHANNEL_SIZE']<=16384
assert all(0xE000<=address<0xF400 or 0xF800<=address<=0xFFFF for address in rom)
rom_symbols=read_symbols(b/'boot.sym')
for slot, name in [(0xF821,'rom_boot_status'),(0xF824,'rom_boot_pulse'),(0xF827,'rom_boot_image')]:
    assert bytes(rom[slot+i] for i in range(3)) == bytes([0x7E])+rom_symbols[name].to_bytes(2,'big')
assert symbols['COMMON_USED_END']==0xE000
report=dict(installed_bytes=524288,physical_frame_bytes=16384,total_frames=32,
 reserved_frames=3,admissible_frames=29,core_code_bytes=symbols['CORE_END'],
 banked_handle_metadata_bytes=symbols['HANDLE_COUNT']*8,
 common_address_reservation=8192,common_physical_reservation=16384,
 rom_address_reservation=8192,io_overlay=1024,usable_rom=7168,
 rom_populated=len(rom),kernel_stack_bytes=symbols['KERNEL_STACK']-symbols['KERNEL_CANARY']-2,
 emergency_stack_bytes=symbols['EMERGENCY_STACK']-symbols['EMERGENCY_CANARY']-2,
 process_capacity=8,channel_records=20,banked_channel_metadata_bytes=640,handle_records=64,request_records=8,
 boot_feedback_common_bytes=4,
 channel_payload_frame_bytes=16384,request_pool_frames=1,
 hashes={f:hashlib.sha256((b/f).read_bytes()).hexdigest() for f in ['boot.ihex','mlos.bin','console.img']})
(b/'runtime-budget.json').write_text(json.dumps(report,indent=2)+'\n')
config=(root/'hardware.cfg').read_text().replace('SECTORS=512','SECTORS=4096\nIMAGE='+str((b/'console.img').resolve()))
(b/'runtime.cfg').write_text(config)
(b/'mlos.session').write_text('CONFIG=runtime.cfg\nROM=boot.ihex\nROM_FORMAT=ihex\nCF=console.img\nCF_SECTORS=4096\nCPU=HD6309\nTRUE_CLOCK_HZ=3000000\nSHOW_SERIAL=true\nSHOW_CONTROL=true\n')
print(f"runtime core={report['core_code_bytes']}/14336 +512 handle +640 channel bytes; ROM={len(rom)}/7168; common=8192/8192")
