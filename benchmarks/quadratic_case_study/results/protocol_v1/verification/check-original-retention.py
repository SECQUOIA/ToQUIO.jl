"""Compare every pre-amendment member with its digest in the complete packet index."""
import argparse, datetime as dt, hashlib, json
from pathlib import Path

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def check(packet, baseline, output):
    index_path=packet/'index.json'
    index=json.loads(index_path.read_text())
    original=json.loads(baseline.read_text())
    previous='analysis-history/efcc66430756a66f0ffddd58f144cfac74ac30ce/'
    if original['file_count']!=len(original['files']):
        raise ValueError('Invalid baseline inventory count')
    relocations={}
    for name,entry in original['files'].items():
        target=previous+name if name.startswith('analysis-source/') or name in ('analysis-files.json','postprocessing-amendment.toml') else name
        if name=='progress.toml':target='processes/terminal-progress-before-packaging.toml'
        if index['files'].get(target)!=entry:
            raise ValueError('Original member differs: '+name)
        if target!=name:relocations[name]=target
    record=dict(status='PASS',kind='original-member-retention-index-comparison',
        observed_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
        source_commit=index['source_commit'],postprocessing_commit=index['postprocessing_commit'],
        index_sha256=sha(index_path),baseline_inventory_sha256=sha(baseline),
        original_file_count=len(original['files']),
        original_bytes=sum(e['size'] for e in original['files'].values()),
        complete_packet_members=len(index['files']),relocations=relocations,
        scope='Every original member size/hash occurs in the complete index at its original or documented retained-history/progress location; compressed-stream integrity is independently checked by extraction',
        numerical_measurements_repeated=False)
    with output.open('x') as stream:json.dump(record,stream,sort_keys=True,indent=2);stream.write('\n')
    print(json.dumps({k:v for k,v in record.items() if k!='relocations'},sort_keys=True))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packet',type=Path);parser.add_argument('baseline',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();check(args.packet,args.baseline,args.output)
