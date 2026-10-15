#!/usr/bin/env python3
"""Bounded, single-worker campaign supervisor. No provider APIs or hidden retries."""
from __future__ import annotations
import argparse, fcntl, hashlib, json, os, shutil, subprocess, tarfile, time, tomllib
from pathlib import Path

STUDY = Path('benchmarks/quadratic_case_study')

def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def atomic_json(path, record):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(record, sort_keys=True, indent=2) + '\n')
    temporary.replace(path)

def read_toml(path):
    with open(path, 'rb') as source:
        return tomllib.load(source)

def write_flat_toml(path, record):
    # Only scalar supervisor fields; never serialize untrusted strings as code.
    lines = []
    for key, value in record.items():
        if isinstance(value, str): value = json.dumps(value)
        elif isinstance(value, bool): value = str(value).lower()
        lines.append(f'{key} = {value}\n')
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(''.join(lines)); temporary.replace(path)

def extract_checked(archive, output, *, allowance=536870912):
    output.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:gz') as bundle:
        members = bundle.getmembers(); names = set(); total = 0
        for item in members:
            relative = Path(item.name)
            if (not item.isfile() or relative.is_absolute() or '..' in relative.parts
                    or item.name in names):
                raise ValueError('Unsafe or duplicate archive member')
            names.add(item.name); total += item.size
            if total > allowance: raise ValueError('Archive allocation allowance exceeded')
        for item in members:
            path = output / item.name; path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists(): raise ValueError('Refuse archive overwrite')
            with bundle.extractfile(item) as source, open(path, 'wb') as target:
                shutil.copyfileobj(source, target)


def verify_inputs(snapshot, inputs):
    index = json.loads((snapshot / STUDY / 'inputs/index.json').read_text())
    for relative, expected in index['files'].items():
        if digest(inputs / relative) != expected: raise ValueError('Extracted input differs from committed inventory')
    actual = {str(p.relative_to(inputs)) for p in inputs.rglob('*') if p.is_file()}
    if actual != set(index['files']): raise ValueError('Concrete input member inventory mismatch')
    return index

def planned_ids(inventory, arms):
    result = {}
    for row in inventory:
        identifier = row['instance_id']
        for arm in arms:
            result[f'{identifier}--{arm}'] = dict(kind='structural', instance_id=identifier,
                                                arm=arm, source_hash=row['sha256'])
        if row['direct']:
            result[f'{identifier}--direct'] = dict(kind='direct', instance_id=identifier,
                                                  source_hash=row['sha256'])
    return result

def docker_arguments(snapshot, inputs, output, name):
    label = hashlib.sha256(str(output).encode()).hexdigest()
    args = ['docker', 'run', '--name', name, '--label', f'toquio.fresh-campaign={label}', '--memory', '12g', '--memory-swap', '12g',
            '--cpus', '1', '--mount', f'type=bind,src={snapshot},dst=/workspace,readonly',
            '--mount', f'type=bind,src={inputs},dst=/inputs,readonly',
            '--mount', f'type=bind,src={output},dst=/output',
            '--mount', 'type=volume,src=toquio-dell-study-depot,dst=/depot',
            '--mount', 'type=volume,src=toquio-cqt54-depot,dst=/base-depot,readonly',
            '--env', 'JULIA_DEPOT_PATH=/depot:/base-depot:/host-depot',
            '--env', 'JULIA_NUM_THREADS=1', '--env', 'OPENBLAS_NUM_THREADS=1',
            '--env', 'JULIA_NUM_PRECOMPILE_TASKS=1']
    # Forward only the existing licensed-solver configuration, never other service
    # credentials. Values never enter the public records or command diagnostics.
    host_depot=Path.home()/'.julia'
    if host_depot.is_dir():
        args += ['--mount',f'type=bind,src={host_depot},dst=/host-depot,readonly']
    license_path = os.environ.get('GRB_LICENSE_FILE', '')
    if license_path and Path(license_path).is_file():
        args += ['--mount', f'type=bind,src={Path(license_path).resolve()},dst=/run/gurobi.lic,readonly',
                 '--env', 'GRB_LICENSE_FILE=/run/gurobi.lic']
    elif license_path:
        args += ['--env', 'GRB_LICENSE_FILE']
    for key in ('GRB_WLSACCESSID', 'GRB_WLSSECRET', 'GRB_LICENSEID'):
        if key in os.environ: args += ['--env', key]
    return args

def start(args):
    source = args.source.resolve(); output = args.output.resolve()
    if output.exists(): raise ValueError('Refuse existing campaign output; use resume')
    sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True):
        raise ValueError('Executable source must be a clean committed tree')
    protocol = read_toml(source / STUDY / 'protocol.toml')
    if protocol['status'] != 'frozen': raise ValueError('Protocol is not frozen')
    output.mkdir(parents=True)
    snapshot = output / 'source'; snapshot.mkdir()
    # git archive supplies tracked files from the exact source commit. Local user
    # files and mutable worktree files are not execution inputs.
    archive = output / 'source.tar'
    with open(archive, 'wb') as target:
        subprocess.run(['git', '-C', str(source), 'archive', sha], stdout=target, check=True)
    with tarfile.open(archive) as bundle:
        for item in bundle:
            if item.issym() or item.islnk() or '..' in Path(item.name).parts:
                raise ValueError('Unexpected source archive member')
        bundle.extractall(snapshot, filter='data')
    archive.unlink()
    # Manifest must be committed in the study profile, preserving exact pins.
    if not (snapshot / STUDY / 'Manifest.toml').is_file(): raise ValueError('Missing frozen Manifest')
    inputs = output / 'inputs'; inputs.mkdir()
    index = json.loads((snapshot / STUDY / 'inputs/index.json').read_text())
    for name, expected in sorted(index['archives'].items()):
        archive = snapshot / STUDY / 'inputs' / name
        if digest(archive) != expected: raise ValueError('Frozen input archive mismatch')
        extract_checked(archive, inputs)
    verify_inputs(snapshot, inputs)
    inventory = read_toml(inputs / 'inventory.toml')['instances']
    planned = planned_ids(inventory, protocol['arms'])
    if len(planned) != 3132: raise ValueError('Unexpected planned-cell denominator')
    atomic_json(output / 'plan.json', planned)
    files = {str(path.relative_to(snapshot)): digest(path) for path in snapshot.rglob('*') if path.is_file()}
    atomic_json(output / 'source-files.json', files)
    image_id = subprocess.check_output(['docker','image','inspect','--format','{{.Id}}','julia:1.10.11'],text=True).strip()
    write_flat_toml(output / 'run.toml', dict(schema_version=1, source_commit=sha,
        protocol_sha256=digest(snapshot / STUDY / 'protocol.toml'), backend=args.backend,
        started_unix=time.time(), campaign_wall_seconds=protocol['resources']['campaign_wall_seconds'],
        julia_image='julia:1.10.11', julia_image_id=image_id, memory_bytes=12884901888, cpu_threads=1,
        publication_logs='structured-whitelist-only-no-process-stdout'))
    resume(output)

def reconcile_orphans(output):
    label = hashlib.sha256(str(output).encode()).hexdigest()
    containers = subprocess.check_output(['docker','ps','-aq','--filter',
        f'label=toquio.fresh-campaign={label}'],text=True).split()
    for container in containers:
        state = subprocess.check_output(['docker','inspect','--format','{{.State.Running}}',container],text=True).strip()
        if state == 'true':
            subprocess.run(['docker','kill',container],stdout=subprocess.DEVNULL,check=True,timeout=30)
            subprocess.run(['docker','wait',container],stdout=subprocess.DEVNULL,check=True,timeout=30)
        state = subprocess.check_output(['docker','inspect','--format','{{.State.Running}}',container],text=True).strip()
        if state != 'false': raise RuntimeError('Own previous worker is not confirmed stopped')

def resume(output):
    output = output.resolve()
    reconcile_orphans(output)
    run = read_toml(output / 'run.toml')
    snapshot = output / 'source'; inputs = output / 'inputs'
    for relative, expected in json.loads((output / 'source-files.json').read_text()).items():
        if digest(snapshot / relative) != expected: raise ValueError('Execution source changed')
    verify_inputs(snapshot, inputs)
    planned = json.loads((output / 'plan.json').read_text())
    (output / 'cells').mkdir(exist_ok=True)
    # Recover a previous process interruption without attempting that cell again.
    for marker in (output / 'attempts').glob('*.toml'):
        identifier = marker.stem
        if not (output / 'cells' / marker.name).exists():
            record_failure(output, identifier, planned, run, 'interrupted-prior-attempt')
    restarts = len(list((output / 'processes').glob('*.json')))
    (output / 'processes').mkdir(exist_ok=True)
    while len(list((output / 'cells').glob('*.toml'))) < len(planned):
        if time.time() - run['started_unix'] >= run['campaign_wall_seconds']:
            for identifier in planned:
                if not (output / 'cells' / f'{identifier}.toml').exists():
                    record_failure(output, identifier, planned, run, 'campaign-clock-censored')
            break
        restarts += 1
        name = f'toquio-fresh-campaign-{int(run["started_unix"])}-{restarts}'
        # Logs deliberately stay outside the exportable numerical packet.
        private_log = output.parent / f'{name}.private.log'
        command = docker_arguments(snapshot, inputs, output, name) + [
            run['julia_image_id'], 'julia', '--startup-file=no',
            '--project=/workspace/benchmarks/quadratic_case_study',
            '/workspace/benchmarks/quadratic_case_study/worker.jl', '/inputs', '/output', run['source_commit']]
        (output / 'progress.toml').unlink(missing_ok=True)
        terminal_before = len(list((output / 'cells').glob('*.toml')))
        beginning = time.time(); last = None; phase_started = beginning; phase = None; reason = None
        atomic_json(output / 'processes' / f'{restarts:04d}.json',
                    dict(process=restarts, container=name, state='allocated-before-launch', started_unix=beginning))
        with open(private_log, 'wb') as log:
            child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            while child.poll() is None:
                time.sleep(2)
                path = output / 'progress.toml'
                if path.exists():
                    current = path.read_bytes()
                    if current != last:
                        last = current; phase = tomllib.loads(current.decode()); phase_started = time.time()
                allowance = phase['watchdog_seconds'] if phase else 600
                if time.time() - phase_started > allowance:
                    reason = 'phase-clock-censored'; break
                if time.time() - run['started_unix'] >= run['campaign_wall_seconds']:
                    reason = 'campaign-clock-censored'; break
            if reason:
                subprocess.run(['docker', 'kill', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            code = child.wait()
        process = dict(process=restarts, exit_code=code, wall_seconds=time.time()-beginning,
                       stop_reason=reason or 'process-exit', container=name)
        atomic_json(output / 'processes' / f'{restarts:04d}.json', process)
        if code == 0: break
        if phase and phase['cell_id'] in planned:
            identifier = phase['cell_id']
            path = output / 'cells' / f'{identifier}.toml'
            if not path.exists(): record_failure(output, identifier, planned, run, reason or 'process-error-or-memory-limit')
        else:
            raise RuntimeError('Worker failed before a planned cell; inspect private setup log')
        if len(list((output / 'cells').glob('*.toml'))) <= terminal_before:
            raise RuntimeError('Failed process made no terminal-cell progress; no automatic restart')
        # Every restart must consume a new terminal cell, never retry that cell.
    actual = {path.stem for path in (output / 'cells').glob('*.toml')}
    if actual != set(planned): raise RuntimeError('Campaign ended with missing or extra cells')
    atomic_json(output / 'completion.json', dict(planned_cells=len(planned), terminal_cells=len(actual),
        finished_unix=time.time(), elapsed_seconds=time.time()-run['started_unix']))

def record_failure(output, identifier, plan, run, reason):
    record = dict(plan[identifier], cell_id=identifier, status=reason,
                  source_commit=run['source_commit'], protocol_sha256=run['protocol_sha256'])
    write_flat_toml(output / 'cells' / f'{identifier}.toml', record)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    new = sub.add_parser('start'); new.add_argument('--source', type=Path, required=True)
    new.add_argument('--output', type=Path, required=True)
    new.add_argument('--backend', choices=['Gurobi', 'SCIP'], required=True)
    again = sub.add_parser('resume'); again.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    lock_path = args.output.resolve().with_suffix('.supervisor.lock')
    lock_path.parent.mkdir(parents=True,exist_ok=True)
    with open(lock_path,'a') as lock:
        fcntl.flock(lock.fileno(),fcntl.LOCK_EX | fcntl.LOCK_NB)
        start(args) if args.action == 'start' else resume(args.output)
