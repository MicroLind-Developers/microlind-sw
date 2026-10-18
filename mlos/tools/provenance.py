#!/usr/bin/env python3
"""Retain exact local revisions, tool versions/options and artifact hashes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--build',type=Path,required=True)
parser.add_argument('--assembler',required=True)
parser.add_argument('--cmoc',required=True)
parser.add_argument('--simulator',type=Path,required=True)
args=parser.parse_args()
def run(command,cwd=None):
    result=subprocess.run(command,cwd=cwd,capture_output=True,text=True,timeout=10)
    if result.returncode:raise SystemExit(f'{command}: {result.stderr}')
    return result.stdout.strip()
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
repos={}
for name,repo in [('software',root.parent),('simulator',root.parent.parent/'microlind-sim'),('hardware',root.parent.parent/'microlind-hw')]:
    repos[name]={'revision':run(['git','rev-parse','HEAD'],repo),'status':run(['git','status','--porcelain'],repo)}
    files=run(['git','ls-files','--cached','--others','--exclude-standard'],repo).splitlines()
    digest=hashlib.sha256()
    for filename in sorted(set(files)):
        path=repo/filename
        if path.is_file():
            digest.update(filename.encode()+b'\0'+path.read_bytes()+b'\0')
    repos[name]['source_tree_sha256']=digest.hexdigest()
simulator=args.simulator.resolve(strict=True)
record={'target':{'ram_bytes':524288,'frames':32,'native_md':1,'diagnostic_sim_cpu_hz':3000000,'runtime_sim_cpu_hz':3000000,'board_cpu_hz_candidate':3000000},
        'tools':{'lwasm':run([args.assembler,'--version']),'cmoc':run([args.cmoc,'--version']),
                 'lwlink':run(['lwlink','--version']),'python':run(['python3','--version']),
                 'cmake':run(['cmake','--version']).splitlines()[0],
                 'cc':run(['cc','--version']).splitlines()[0]},
        'assembler_options':'-3 -p autobranchlength -f raw (core/app), -f ihex (ROM)',
        'cmoc_options':'-Werror --void-target --srec --org=0420 --no-relocate; harness limit=3A00, runtime limits in Makefile',
        'repositories':repos,'simulator_binary':{'path':str(simulator),'sha256':sha(simulator)},
        'artifacts':{name:sha(args.build/name) for name in ['mlos.ihex','core.raw','app.raw','budget.json','boot.ihex','mlos.bin','console.img','runtime-budget.json']}}
(args.build/'provenance.json').write_text(json.dumps(record,indent=2)+'\n')
print('Retained build/provenance.json with revisions, source hashes, options and image hashes')
