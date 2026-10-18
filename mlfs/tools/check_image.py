#!/usr/bin/env python3
"""Offline MLFS 1.1.0/512 validator. Repair only a proven allocation bitmap.

No journal or controller-cache durability is implied. Structural damage and
cross-links require restoring from backup; this tool never guesses ownership.
"""
import argparse
import os
import stat
import tempfile
import struct
from pathlib import Path

class Corrupt(ValueError):
    pass

def word(data, offset):
    return struct.unpack_from('>I', data, offset)[0]

def inspect(image: bytes, partition=0):
    image = bytes(image)
    def require(ok, message):
        if not ok:
            raise Corrupt(message)
    require(len(image) >= 512 and len(image) % 512 == 0, 'truncated device')
    require(image[:7] == b'MLPT\x01\x01\0', 'unsupported MLPT')
    count = int.from_bytes(image[7:9], 'big')
    require(1 <= count <= 16 and 0 <= partition < count, 'partition index/count')
    partitions = []
    for i in range(count):
        off = 9 + 24*i
        start, blocks = struct.unpack_from('>II', image, off)
        kind, shift = image[off+8:off+10]
        require(9 <= shift <= 16 and start > 0 and blocks > 0, 'partition geometry')
        end = start + (blocks << (shift-9))
        require(end <= len(image)//512, 'partition beyond device')
        require(all(end <= a or start >= b for a,b in partitions), 'overlapping partitions')
        partitions.append((start,end))
    off = 9 + partition*24
    start, total = struct.unpack_from('>II', image, off)
    require(image[off+8:off+10] == bytes([1,9]), 'only MLFS with 512-byte blocks supported')
    sb = bytearray(image[start*512:(start+1)*512])
    require(sb[:8] == b'MLFS\x01\x01\0\x09', 'unsupported MLFS')
    checksum = word(sb,45)
    sb[45:49] = bytes(4)
    require(sum(sb) == checksum, 'superblock checksum')
    require(sb[8] in (0,1), 'unknown clean/dirty state')
    require(word(sb,9) == total, 'partition/superblock size disagreement')
    bitmap, bitmap_blocks, root, root_blocks = struct.unpack_from('>IIII',sb,13)
    require(bitmap >= 1 and bitmap_blocks > 0 and root >= bitmap+bitmap_blocks and root_blocks > 0 and root+root_blocks <= total, 'metadata extents')
    require(bitmap_blocks*4096 >= total, 'short allocation bitmap')
    used = bytearray((total+7)//8)
    def mark(first, size):
        require(size > 0 and first >= 0 and first+size <= total, 'extent outside partition')
        for block in range(first,first+size):
            mask = 1 << (block%8)
            require(not (used[block//8]&mask), f'cross-linked block {block}')
            used[block//8] |= mask
    # The target allocator reserves the entire metadata prefix.
    mark(0,root+root_blocks)
    files = 0
    def directory(first, blocks, depth):
        nonlocal files
        require(depth <= 8, 'directory depth exceeds target limit')
        names = set()
        for pos in range((start+first)*512,(start+first+blocks)*512,128):
            entry = image[pos:pos+128]
            if not entry[0]:
                continue
            require(entry[0] == 1 and entry[1]&3 in (1,2), 'invalid directory entry')
            name = entry[16:64].split(b'\0',1)[0]
            require(0 < len(name) < 48 and b'/' not in name and name not in (b'.',b'..'), 'invalid name')
            require(name not in names, 'duplicate name in directory')
            names.add(name)
            require(entry[14] == 1 and entry[15] <= 1 and word(entry,96) == 0, 'unsupported extent layout')
            first_block, block_count = struct.unpack_from('>II',entry,64)
            require(first_block >= root+root_blocks and word(entry,2) <= block_count*512, 'invalid file capacity')
            mark(first_block,block_count)
            files += 1
            if entry[1]&1:
                directory(first_block,block_count,depth+1)
    directory(root,root_blocks,0)
    disk_bitmap = image[(start+bitmap)*512:(start+bitmap+bitmap_blocks)*512]
    mismatches = sum(bool((used[b//8]^disk_bitmap[b//8]) & (1<<(b%8))) for b in range(total))
    return dict(start=start, total=total, bitmap=bitmap, bitmap_blocks=bitmap_blocks,
                expected=used, dirty=bool(sb[8]), mismatches=mismatches, files=files,
                used=sum(x.bit_count() for x in used))

def repair(image: bytes, report):
    result = bytearray(image)
    offset = (report['start']+report['bitmap'])*512
    # Preserve undefined bits beyond the volume's declared block count.
    for b in range(report['total']):
        mask = 1<<(b%8)
        result[offset+b//8] = (result[offset+b//8]&~mask)|(report['expected'][b//8]&mask)
    offset = report['start']*512
    result[offset+8] = 0
    result[offset+45:offset+49] = bytes(4)
    struct.pack_into('>I',result,offset+45,sum(result[offset:offset+512]))
    return bytes(result)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image',type=Path)
    parser.add_argument('--partition',type=int,default=0)
    parser.add_argument('--repair',action='store_true',help='rebuild bitmap and clear dirty only after structural validation')
    args=parser.parse_args()
    try:
        data=args.image.read_bytes()
        report=inspect(data,args.partition)
        if args.repair:
            if not stat.S_ISREG(args.image.stat().st_mode):
                raise Corrupt("repair requires a regular offline image file")
            target=args.image.resolve()
            fd,temporary=tempfile.mkstemp(prefix=target.name+".repair-",dir=target.parent)
            try:
                with os.fdopen(fd,"wb") as output:
                    output.write(repair(data,report));output.flush();os.fsync(output.fileno())
                os.chmod(temporary,stat.S_IMODE(target.stat().st_mode))
                os.replace(temporary,target)
            finally:
                if os.path.exists(temporary):os.unlink(temporary)
            report=inspect(args.image.read_bytes(),args.partition)
        print(f"files={report['files']} used={report['used']}/{report['total']} dirty={int(report['dirty'])} bitmap_errors={report['mismatches']}")
        return 1 if report['dirty'] or report['mismatches'] else 0
    except (OSError,ValueError,struct.error) as error:
        print(f'INVALID: {error}')
        return 2
if __name__=='__main__':
    raise SystemExit(main())
