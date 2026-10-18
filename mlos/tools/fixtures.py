#!/usr/bin/env python3
"""Produce reproducible disposable images. S03 defines/validates mlos.bin later."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--cc',default='cc')
args=parser.parse_args()
args.output.mkdir(parents=True,exist_ok=True)
# Never takes a device path or an arbitrary image destination; output is a directory.
with tempfile.TemporaryDirectory(prefix='mlos-fixtures-') as temporary:
    work=Path(temporary)
    builder=work/'builder'
    subprocess.run([args.cc,'-std=c99','-Wall','-Wextra','-Werror',
        '-Dtime=fixture_time','-Dclock=fixture_clock','-Drand=fixture_rand',
        '-I',str(root.parent/'mlfs/lib/include'),str(root/'tests/make_fixture.c'),
        str(root.parent/'mlfs/lib/src/mlfs.c'),'-o',str(builder)],check=True,timeout=30)
    images=[]
    for i in range(2):
        path=work/f'{i}.img'
        subprocess.run([str(builder),str(path)],check=True,timeout=10)
        images.append(path.read_bytes())
    if images[0]!=images[1]:
        raise SystemExit('fixture build is not reproducible')
    pristine=images[0]
fixtures={'pristine.img':pristine,
          'bad-mlpt.img':b'BAD!'+pristine[4:],
          'bad-superblock.img':pristine[:512]+b'BAD!'+pristine[516:],
          'truncated.img':pristine[:700]}
manifest={}
for name,data in fixtures.items():
    (args.output/name).write_bytes(data)
    manifest[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
(args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Reproducible MLFS fixtures: pristine, bad MLPT, bad superblock, truncated')
