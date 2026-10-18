#!/usr/bin/env python3
"""Host image/repair contracts complement actual ROM/core rejection tests."""
import argparse
import struct
import sys
import unittest
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'tools'))
from images import Segment,application_image,kernel_image,unpack_kernel
sys.path.insert(0,str(root.parent/'mlfs/tools'))
from check_image import inspect,repair,Corrupt
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);args=p.parse_args()
base=(args.build/'console.img').read_bytes()

class Images(unittest.TestCase):
    def test_kernel_encoding_and_checksum(self):
        payload=bytes(range(256))*7
        data=kernel_image(payload,17)
        self.assertEqual(len(data),20+len(payload))
        self.assertEqual(data[:4],b'MLK1')
        self.assertEqual(unpack_kernel(data),(payload,17))
        bad=bytearray(data);bad[-1]^=1
        with self.assertRaises(ValueError):unpack_kernel(bad)
    def test_kernel_rejects_footprint_and_entry(self):
        for data,entry in [(b'',0),(b'x'*16385,0),(b'x',1)]:
            with self.assertRaises(ValueError):kernel_image(data,entry)
    def test_application_layout(self):
        for resident in [1,3,7]:
            end=(resident.bit_length()*16384)-128
            data=application_image([Segment(0x400,b'code',8)],0x400,resident=resident,stack=end)
            self.assertEqual(data[:4],b'MLX1')
            self.assertEqual(int.from_bytes(data[24:28],'big'),sum(data[:24]+bytes(4)+data[28:])&0xffffffff)
    def test_application_preflight(self):
        cases=[([Segment(0x3f80,b'x')],0x3f80,{}),
               ([Segment(0x400,b'x',4)],0x401,{}),
               ([Segment(0x400,b'xx'),Segment(0x401,b'x')],0x400,{}),
               ([Segment(0x400,b'x')],0x400,dict(resources=1)),
               ([Segment(0x400,b'x')],0x400,dict(stack=0x4000)),
               ([Segment(0x8000,b'x')],0x8000,{})]
        for segments,entry,options in cases:
            with self.subTest(entry=entry,options=options):
                with self.assertRaises(ValueError):application_image(segments,entry,**options)
    def test_clean_volume(self):
        report=inspect(base)
        self.assertFalse(report['dirty']);self.assertEqual(report['mismatches'],0)
        self.assertEqual(repair(base,report),base)
    def test_dirty_state_requires_explicit_repair(self):
        image=bytearray(base);offset=inspect(base)['start']*512
        image[offset+8]=1;image[offset+45:offset+49]=bytes(4)
        struct.pack_into('>I',image,offset+45,sum(image[offset:offset+512]))
        report=inspect(image);self.assertTrue(report['dirty'])
        fixed=repair(image,report);self.assertEqual(fixed,base)
    def test_bitmap_repairs_only_proven_ownership(self):
        image=bytearray(base);report=inspect(base)
        offset=(report['start']+report['bitmap'])*512
        image[offset]^=1
        broken=inspect(image);self.assertEqual(broken['mismatches'],1)
        self.assertEqual(repair(image,broken),base)
    def test_crosslink_is_not_repairable(self):
        image=bytearray(base);start=inspect(base)['start'];sb=start*512
        root=(start+int.from_bytes(image[sb+21:sb+25],'big'))*512
        image[root+128+64:root+128+72]=image[root+64:root+72]
        with self.assertRaises(Corrupt):inspect(image)
    def test_truncation_and_unknown_format(self):
        for data in [base[:-1],b'FAIL'+base[4:]]:
            with self.assertRaises(Corrupt):inspect(data)

unittest.main(argv=[sys.argv[0]])
