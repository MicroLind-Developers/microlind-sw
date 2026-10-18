#!/usr/bin/env python3
import argparse
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'bios/tools'))
from image_formats import image_bytes,read_records
from images import Segment,application_image
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path)
for name,default in [('entry',0x400),('resident',1),('resources',0),('stack',0x3f80),('stack-size',1024),('bss-start',0),('bss-size',0)]:p.add_argument('--'+name,type=lambda s:int(s,0),default=default)
p.add_argument('--fill-gap',type=int,default=0);p.add_argument('--zero',action='append',default=[]);p.add_argument('--overlay',type=Path);p.add_argument('--cmoc-map',type=Path)
a=p.parse_args();image=image_bytes(read_records(a.source))
if a.overlay:image.update(image_bytes(read_records(a.overlay)))
if a.cmoc_map:
    import re
    contents=a.cmoc_map.read_text()
    start=re.search(r'Symbol: s_bss .*? = ([0-9A-Fa-f]+)',contents)
    size=re.search(r'Symbol: l_bss .*? = ([0-9A-Fa-f]+)',contents)
    if not start or not size:raise ValueError('missing CMOC BSS map')
    a.bss_start=int(start[1],16);a.bss_size=int(size[1],16)
if a.fill_gap:
    original=sorted(image)
    for left,right in zip(original,original[1:]):
        if right-left-1<=a.fill_gap:
            for address in range(left+1,right):image[address]=0
segments=[];addresses=sorted(image)
while addresses:
    start=addresses[0];n=1
    while n<len(addresses) and addresses[n]==start+n:n+=1
    segments.append(Segment(start,bytes(image[x] for x in addresses[:n])))
    addresses=addresses[n:]
for spec in a.zero:
    address,size=map(lambda x:int(x,0),spec.split(':'));segments.append(Segment(address,b'',size))
if a.bss_size:segments.append(Segment(a.bss_start,b'',a.bss_size))
a.output.write_bytes(application_image(segments,a.entry,resident=a.resident,resources=a.resources,stack=a.stack,stack_size=a.stack_size))
