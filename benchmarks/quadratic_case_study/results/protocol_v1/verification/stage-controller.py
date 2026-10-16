"""Run terminal-only amended postprocessing once, with exclusive ownership."""
import datetime as dt,fcntl,hashlib,json,subprocess,sys
from pathlib import Path
RUNNER=Path('/tmp/toquio-run-fresh-final-stage-v2.py')
RUNNER_SHA='22a7c542988805a12133b6320e1714b6842ef8909cb91ff8e2cb3012f611fb9f'
OUT=Path('/tmp/toquio-fresh-final-artifacts-v2')
RECORD=Path('/tmp/toquio-fresh-final-pipeline-v2.json')
STAGES=('raw-report','raw-plots','pack','bootstrap','extract','view-report','view-plots','replay')
def stamp():return dt.datetime.now(dt.timezone.utc).isoformat()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def update(record,phase,**extra):
    record.update(phase=phase,observed_utc=stamp(),**extra)
    temp=RECORD.with_suffix('.tmp');temp.write_text(json.dumps(record,sort_keys=True,indent=2)+'\n');temp.replace(RECORD)
    print(json.dumps({'phase':phase,'observed_utc':record['observed_utc']}),flush=True)
def main():
    with Path('/tmp/toquio-fresh-final-pipeline.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if RECORD.exists() or OUT.exists():raise RuntimeError('Refuse existing new-attempt output')
        record={'kind':'amended-postprocessing-pipeline','runner_sha256':RUNNER_SHA,'measurement_reruns':False,'completed':{}}
        update(record,'preflight')
        try:
            for stage in STAGES:
                if sha(RUNNER)!=RUNNER_SHA:raise RuntimeError('Reviewed runner changed')
                update(record,stage)
                subprocess.run([sys.executable,'-B',str(RUNNER),stage],check=True)
                path=OUT/(stage+'.proof.json');proof=json.loads(path.read_text())
                if proof['status']!='PASS' or proof['postprocessing_commit']!='3db4e8a349adeebb62bf1f99351768072c27a3a1':raise RuntimeError('Wrong stage proof')
                for controls in (proof['effective_controls_before'],proof['effective_controls_after']):
                    if controls['memory.max']!=str(4*1024**3) or controls['memory.swap.max']!='0' or controls['memory.swap.current']!='0' or controls['cpu.max']!='100000 100000':raise RuntimeError('Invalid effective stage controls')
                record['completed'][stage]=sha(path)
                update(record,stage+'-pass')
            update(record,'terminal-postprocessing-pass')
        except Exception as exc:
            update(record,'stopped-for-inspection',reason=str(exc));raise
if __name__=='__main__':main()
