#!/usr/bin/env python3
"""Pack the fixed-link trusted block driver ABI; callbacks are code offsets."""
import argparse,struct
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path)
p.add_argument('--bind',type=lambda x:int(x,0),required=True);p.add_argument('--poll',type=lambda x:int(x,0),required=True);p.add_argument('--stop',type=lambda x:int(x,0),required=True);p.add_argument('--bss',type=lambda x:int(x,0),default=0)
a=p.parse_args();data=a.source.read_bytes();entries=[a.bind-0x4000,a.poll-0x4000,a.stop-0x4000]
if not data or len(data)+a.bss>16384 or any(not 0<=e<len(data) for e in entries):raise ValueError('module range')
h=bytearray(struct.pack('>4s10HII',b'MLD1',1,32,1,0x4000,len(data),a.bss,*entries,1,0,0));image=h+data;struct.pack_into('>I',image,24,sum(image)&0xffffffff);a.output.write_bytes(image)
