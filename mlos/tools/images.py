#!/usr/bin/env python3
"""Versioned byte-oriented MLOS image encoders and validators."""
from dataclasses import dataclass
import struct
KERNEL=struct.Struct('>4s6HI')

def kernel_image(payload:bytes,entry:int=0)->bytes:
    if not payload or len(payload)>16384 or not 0<=entry<len(payload):
        raise ValueError('kernel payload/entry outside physical core frame')
    return KERNEL.pack(b'MLK1',1,0,0,entry,len(payload),16384,sum(payload)&0xffffffff)+payload

def unpack_kernel(image:bytes)->tuple[bytes,int]:
    if len(image)<20:raise ValueError('truncated kernel header')
    magic,version,kind,load,entry,size,memory,checksum=KERNEL.unpack_from(image)
    payload=image[20:]
    if (magic,version,kind,load,memory)!=(b'MLK1',1,0,0,16384):raise ValueError('unsupported kernel header')
    if not 0<len(payload)==size<=16384 or not 0<=entry<size:raise ValueError('invalid kernel extent')
    if sum(payload)&0xffffffff!=checksum:raise ValueError('kernel checksum')
    return payload,entry

def main():
    import argparse
    from pathlib import Path
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);p.add_argument('--entry',type=lambda s:int(s,0),default=0)
    a=p.parse_args();a.output.write_bytes(kernel_image(a.source.read_bytes(),a.entry))
if __name__=='__main__':main()

@dataclass(frozen=True)
class Segment:
    address:int
    data:bytes
    bss:int=0

def application_image(segments:list[Segment],entry:int,*,resident:int=1,resources:int=0,stack:int=0x3f80,stack_size:int=1024)->bytes:
    if not 1<=len(segments)<=6 or resident not in (1,3,7) or resources & resident or resources&~7:
        raise ValueError('invalid resident/resource/segment layout')
    if stack_size<128 or stack_size>stack or stack+128>0xc000 or stack&1:raise ValueError('invalid fixed stack')
    if any(not (resident & (1 << w)) for w in range((stack-stack_size)//16384,(stack+127)//16384+1)):raise ValueError('stack/argv outside resident maps')
    table=bytearray();payload=bytearray();ranges=[]
    for s in sorted(segments,key=lambda s:s.address):
        end=s.address+len(s.data)+s.bss
        if s.address<0 or not s.address<end<=0xc000 or len(s.data)>65535 or s.bss<0:raise ValueError('segment bounds')
        if any(not(resident&(1<<w)) for w in range(s.address//16384,(end-1)//16384+1)):raise ValueError('segment outside resident maps')
        if s.address<stack+128 and end>stack-stack_size:raise ValueError('segment overlaps stack')
        if ranges and s.address<ranges[-1][1]:raise ValueError('overlapping segments')
        ranges.append((s.address,end));table+=struct.pack('>4H',s.address,len(s.data),s.bss,len(payload));payload+=s.data
    if not any(s.address<=entry<s.address+len(s.data) for s in segments):raise ValueError('entry outside segments')
    if len(payload)+32+len(table)>65535:raise ValueError('file too large')
    header=bytearray(32)
    struct.pack_into('>4s5H4B3H',header,0,b'MLX1',1,32+len(table),entry,stack,stack_size,resident,resources,len(segments),0,128,len(payload),0)
    struct.pack_into('>H',header,28,1)
    image=header+table+payload
    struct.pack_into('>I',image,24,sum(image)&0xffffffff)
    return bytes(image)
