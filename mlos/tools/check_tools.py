#!/usr/bin/env python3
"""Reject an unintended target-toolchain change before assembling fixtures."""
import argparse
import json
from pathlib import Path
import subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--assembler',default='lwasm')
parser.add_argument('--cmoc',default='cmoc')
args=parser.parse_args()
lock=json.loads((Path(__file__).resolve().parents[1]/'toolchain.lock.json').read_text())
for tool,command in [('lwasm',args.assembler),('lwlink','lwlink'),('cmoc',args.cmoc)]:
    version=subprocess.check_output([command,'--version'],text=True,timeout=10).strip()
    if version!=lock[tool]:
        raise SystemExit(f'{tool}: expected {lock[tool]!r}, found {version!r}')
print('Target toolchain matches toolchain.lock.json')
