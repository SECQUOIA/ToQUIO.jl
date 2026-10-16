#!/usr/bin/env python3
"""Manufactured whole-entry-point validation. Run under an OS resource limit."""
import argparse,json,re,shutil,subprocess
from pathlib import Path
from campaign import STUDY,digest,read_toml,write_flat_toml,planned_ids
from report import aggregate,verify

def validate(root,julia,backend):
    root=root.resolve();root.mkdir(parents=True,exist_ok=True)
    if any(root.iterdir()):raise ValueError('Refuse existing validation output')
    repository=Path(__file__).resolve().parents[2]
    snapshot=root/'source';snapshot.mkdir()
    shutil.copy2(repository/'Project.toml',snapshot/'Project.toml')
    shutil.copytree(repository/'src',snapshot/'src')
    (snapshot/'benchmarks').mkdir()
    shutil.copy2(repository/'benchmarks/metropolis.jl',snapshot/'benchmarks/metropolis.jl')
    profile=snapshot/STUDY
    shutil.copytree(repository/STUDY,profile,ignore=shutil.ignore_patterns('__pycache__','inputs','results','.venv'))
    protocolpath=profile/'protocol.toml'
    protocol=read_toml(protocolpath)
    protocolpath.write_text(protocolpath.read_text().replace('status = "'+protocol['status']+'"','status = "frozen"'))
    inputs=root/'inputs';inputs.mkdir()
    command=[julia,'--startup-file=no','--project='+str(profile)]
    subprocess.run(command+[str(profile/'prepare_validation.jl'),str(inputs)],check=True,timeout=300)
    (profile/'inputs').mkdir()
    index=dict(files={str(p.relative_to(inputs)):digest(p) for p in inputs.rglob('*') if p.is_file()},archives={})
    (profile/'inputs/index.json').write_text(json.dumps(index,sort_keys=True))
    (root/'source-files.json').write_text(json.dumps({str(p.relative_to(snapshot)):digest(p)
        for p in snapshot.rglob('*') if p.is_file()},sort_keys=True))
    inventory=read_toml(inputs/'inventory.toml')['instances']
    (root/'plan.json').write_text(json.dumps(planned_ids(inventory,protocol['arms']),sort_keys=True))
    write_flat_toml(root/'run.toml',dict(schema_version=1,source_commit='manufactured-validation-uncommitted',
        protocol_sha256=digest(protocolpath),backend=backend,campaign_kind='manufactured-entrypoint-validation'))
    subprocess.run(command+[str(profile/'worker.jl'),str(inputs),str(root),
        'manufactured-validation-uncommitted'],check=True,timeout=900)
    subprocess.run(command+[str(profile/'replay.jl'),str(root),'6'],check=True,timeout=300)
    summary,structural,direct,batches=aggregate(root,root/'report',allow_incomplete=True)
    if not (len(structural)==24 and len(direct)==4 and len(batches)==18 and
            summary['cell_statuses']=={'measured':28} and summary['verified_chains']==180 and
            not summary['full_execution']):raise ValueError('Manufactured integration coverage failed')
    def rejected_mutation(path,changed):
        original=path.read_bytes()
        try:
            path.write_bytes(changed)
            try:verify(root)
            except ValueError:return
            raise AssertionError('Changed evidence was incorrectly accepted')
        finally:path.write_bytes(original)
    chainpath=next((root/'chains').glob('*.toml'))
    original=chainpath.read_text()
    for key in ('polynomial_sha256','source_projection_sha256'):
        changed=re.sub(r'^'+key+r' = "[0-9a-f]+"',key+' = "'+'0'*64+'"',original,flags=re.M)
        if changed==original:raise AssertionError('Mutation did not change retained identity')
        rejected_mutation(chainpath,changed.encode())
    changed=re.sub(r'^elapsed_seconds = .*','elapsed_seconds = -1.0',original,flags=re.M)
    rejected_mutation(chainpath,changed.encode())
    raw=read_toml(chainpath)
    base=raw['instance_id']+'--'+raw['arm']
    polypath=root/'polynomials'/(base+'.toml')
    rejected_mutation(polypath,polypath.read_bytes()+b'\n# altered retained polynomial bytes\n')
    auditpath=root/'replay-audits'/chainpath.name
    saved=auditpath.read_bytes()
    try:
        auditpath.unlink()
        try:verify(root)
        except ValueError:pass
        else:raise AssertionError('Measured cell accepted an unaudited chain')
    finally:auditpath.write_bytes(saved)
    verify(root)
    print('PASS: corrupted identities, elapsed time, polynomial bytes and missing replay evidence rejected.')
    print(json.dumps(summary,sort_keys=True))
    print('PASS: whole worker, serialization, 180 replay audits, standalone replay and independent report.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path)
    parser.add_argument('--julia',default='julia');parser.add_argument('--backend',choices=['Gurobi','SCIP'],default='SCIP')
    args=parser.parse_args();validate(args.output,args.julia,args.backend)
