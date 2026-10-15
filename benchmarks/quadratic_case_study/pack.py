#!/usr/bin/env python3
"""Deterministic bounded archives; only explicitly listed numerical inputs/outputs."""
import argparse, gzip, hashlib, io, json, tarfile
from pathlib import Path
from campaign import digest, read_toml

MAX_FILE=48*1024*1024
MAX_PACKET=512*1024*1024

def archive_files(root, paths, destination):
    destination.parent.mkdir(parents=True,exist_ok=True)
    with open(destination,'wb') as raw, gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0) as compressed:
        with tarfile.open(fileobj=compressed,mode='w|',format=tarfile.PAX_FORMAT) as bundle:
            for relative in sorted(paths):
                path=root/relative
                if not path.is_file() or path.is_symlink():raise ValueError('Unexpected archive input')
                item=tarfile.TarInfo(str(relative));item.size=path.stat().st_size
                item.mode=0o644;item.uid=item.gid=0;item.mtime=0
                with open(path,'rb') as source:bundle.addfile(item,source)
    if destination.stat().st_size>MAX_FILE:raise ValueError('Split archive exceeds per-file allowance')
    return digest(destination)

def pack_inputs(root, output):
    if output.exists() and any(output.iterdir()):raise ValueError('Refuse existing input archive')
    output.mkdir(parents=True,exist_ok=True)
    files={str(path.relative_to(root)):digest(path) for path in root.rglob('*') if path.is_file()}
    inventory=read_toml(root/'inventory.toml')['instances']
    if len(inventory)!=456:raise ValueError('Incomplete concrete-input grid')
    groups={family:[Path(entry['file']) for entry in inventory if entry['family']==family]
            for family in ('facility','inventory','route_allocation','knapsack')}
    groups['inventory-metadata']=[Path('inventory.toml')]
    archives={name+'.tar.gz':archive_files(root,paths,output/(name+'.tar.gz')) for name,paths in groups.items()}
    index=dict(schema_version=1,files=files,archives=archives,profiles=456,underlying_draws=360)
    (output/'index.json').write_text(json.dumps(index,sort_keys=True,indent=2)+'\n')

def pack_campaign(root, output):
    if not (root/'completion.json').is_file():raise ValueError('Campaign has no terminal coverage record')
    if output.exists() and any(output.iterdir()):raise ValueError('Refuse existing published packet')
    output.mkdir(parents=True,exist_ok=True)
    # Exclude all process stdout, private licensing/configuration and mutable progress.
    groups={'identity':[Path(p) for p in ('run.toml','environment.toml','plan.json','source-files.json','completion.json')]}
    for folder in ('source','inputs','processes','attempts','cells','chains','polynomials','replay-audits'):
        paths=[p.relative_to(root) for p in (root/folder).rglob('*') if p.is_file()]
        if folder in ('chains','polynomials','replay-audits','cells'):
            for family in ('facility','inventory','route_allocation','knapsack'):
                groups[folder+'-'+family]=[p for p in paths if p.name.startswith(family+'-')]
        else:groups[folder]=paths
    expected={p for paths in groups.values() for p in paths}
    # No .tmp or arbitrary unclassified numerical files can disappear silently.
    for folder in ('processes','attempts','cells','chains','polynomials','replay-audits'):
        actual={p.relative_to(root) for p in (root/folder).rglob('*') if p.is_file()}
        if not actual<=expected:raise ValueError('Unclassified retained file; reconcile interruption before export')
    archives={}
    for name,paths in groups.items():
        if paths:archives[name+'.tar.gz']=archive_files(root,paths,output/(name+'.tar.gz'))
    if sum(p.stat().st_size for p in output.glob('*.tar.gz'))>MAX_PACKET:raise ValueError('Packet exceeds byte budget')
    index=dict(schema_version=1,source_commit=read_toml(root/'run.toml')['source_commit'],
        archives=archives,files={str(p):digest(root/p) for p in sorted(expected)})
    (output/'index.json').write_text(json.dumps(index,sort_keys=True,indent=2)+'\n')

def extract_packet(packet,output):
    from campaign import extract_checked
    index=json.loads((packet/'index.json').read_text())
    if output.exists():raise ValueError('Refuse existing extracted packet')
    output.mkdir(parents=True)
    for name,expected in index['archives'].items():
        archive=packet/name
        if digest(archive)!=expected:raise ValueError('Packet archive digest mismatch')
        extract_checked(archive,output)
    actual={str(p.relative_to(output)) for p in output.rglob('*') if p.is_file()}
    if actual!=set(index['files']):raise ValueError('Packet member inventory mismatch')
    if any(digest(output/relative)!=expected for relative,expected in index['files'].items()):
        raise ValueError('Packet member digest mismatch')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['inputs','campaign','extract']);parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path);args=parser.parse_args()
    {'inputs':pack_inputs,'campaign':pack_campaign,'extract':extract_packet}[args.action](args.source,args.output)
