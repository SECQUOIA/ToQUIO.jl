"""Retry only replay with the original campaign's existing read-only depot layers."""
import datetime as dt,fcntl,hashlib,importlib.util,json,subprocess,sys
from pathlib import Path
ROOT=Path('/tmp/toquio-fresh-campaign-v1');OUT=Path('/tmp/toquio-fresh-final-artifacts-v2')
RUNNER=Path('/tmp/toquio-run-fresh-final-stage-v2.py')
RUNNER_SHA='22a7c542988805a12133b6320e1714b6842ef8909cb91ff8e2cb3012f611fb9f'
PRIOR=Path('/tmp/toquio-fresh-final-pipeline-v2.json')
RECORD=Path('/tmp/toquio-fresh-replay-recovery-v3.json')
STAGES=('raw-report','raw-plots','pack','bootstrap','extract','view-report','view-plots','replay')
IMAGE='sha256:5264d4c511b47b3b8c726a9b765bf36bdf153a2e85fc2a314d149fbcb3c7ea1c'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load_stage(inside=False):
 path=Path('/stage.py') if inside else RUNNER
 if sha(path)!=RUNNER_SHA:raise ValueError('Original runner changed')
 spec=importlib.util.spec_from_file_location('frozen_stage',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def main():
 if '--inside' in sys.argv:
  load_stage(inside=True).execute('replay');return
 with Path('/tmp/toquio-fresh-final-pipeline.lock').open('a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  if RECORD.exists() or (OUT/'replay.proof.json').exists():raise ValueError('Refuse repeated recovery')
  prior=json.loads(PRIOR.read_text())
  if prior['phase']!='stopped-for-inspection' or set(prior['completed'])!=set(STAGES[:-1]):raise ValueError('Wrong prior pipeline state')
  observation=json.loads(subprocess.check_output(['docker','inspect','toquio-fresh-final-replay-v2']))[0]
  state=observation['State']
  if state['Running'] or state['ExitCode']!=1 or state['OOMKilled']:raise ValueError('Prior worker not expected terminal')
  stage=load_stage();stage.terminal_guard(ROOT)
  for name in STAGES[:-1]:
   if sha(OUT/(name+'.proof.json'))!=prior['completed'][name]:raise ValueError('Prior proof changed')
  record=dict(kind='replay-depot-environment-recovery',phase='replay',observed_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
   previous_pipeline_sha256=sha(PRIOR),previous_replay_log_sha256=sha(OUT/'replay.log'),
   original_runner_sha256=RUNNER_SHA,recovery_source_sha256=sha(Path(__file__)),
   completed=dict(prior['completed']),measurement_reruns=False,repacking=False,
   correction='Restore the exact original /depot:/base-depot:/host-depot search path; additional base and host package caches are read-only; no license file or provider access',
   prior_terminal=dict(Running=state['Running'],ExitCode=state['ExitCode'],OOMKilled=state['OOMKilled']))
  RECORD.write_text(json.dumps(record,sort_keys=True,indent=2)+'\n')
  command=['docker','run','--name','toquio-fresh-final-replay-v3','--memory','4g','--memory-swap','4g','--cpus','1','--network','none',
   '--mount',f'type=bind,src={ROOT},dst=/campaign,readonly','--mount',f'type=bind,src={OUT},dst=/artifacts',
   '--mount',f'type=bind,src={RUNNER},dst=/stage.py,readonly','--mount',f'type=bind,src={Path(__file__).resolve()},dst=/retry.py,readonly',
   '--mount','type=bind,src=/home/bernalde/.local/bin/uv,dst=/usr/local/bin/uv,readonly',
   '--mount','type=volume,src=toquio-fresh-python-env,dst=/python',
   '--mount','type=volume,src=toquio-dell-study-depot,dst=/depot',
   '--mount','type=volume,src=toquio-cqt54-depot,dst=/base-depot,readonly',
   '--mount','type=bind,src=/home/bernalde/.julia,dst=/host-depot,readonly',
   '--env','UV_CACHE_DIR=/python/cache','--env','UV_PYTHON_INSTALL_DIR=/python/managed',
   '--env','PYTHONDONTWRITEBYTECODE=1','--env','OPENBLAS_NUM_THREADS=1',
   '--env','JULIA_DEPOT_PATH=/depot:/base-depot:/host-depot','--env','JULIA_NUM_THREADS=1','--env','JULIA_NUM_PRECOMPILE_TASKS=1',
   IMAGE,'timeout','--kill-after=30','300','uv','run','--offline','--no-project','--python','3.13.5','python','/retry.py','--inside']
  with (OUT/'replay-retry-v3.log').open('xb') as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
  record.update(observed_utc=dt.datetime.now(dt.timezone.utc).isoformat(),exit_code=result.returncode)
  if result.returncode==0:
   proof=json.loads((OUT/'replay.proof.json').read_text())
   if proof['status']!='PASS' or proof['postprocessing_commit']!='3db4e8a349adeebb62bf1f99351768072c27a3a1':raise ValueError('Wrong replay proof')
   record['completed']['replay']=sha(OUT/'replay.proof.json');record['phase']='terminal-postprocessing-pass'
  else:record['phase']='stopped-for-inspection'
  RECORD.write_text(json.dumps(record,sort_keys=True,indent=2)+'\n');print(json.dumps(record,sort_keys=True));raise SystemExit(result.returncode)
if __name__=='__main__':main()
