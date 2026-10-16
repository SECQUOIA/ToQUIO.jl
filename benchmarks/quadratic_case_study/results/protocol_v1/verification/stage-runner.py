"""Prepared terminal-only postprocessing; never starts or resumes measurements."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path('/tmp/toquio-fresh-campaign-v1')
OUT = Path('/tmp/toquio-fresh-final-artifacts-v2')
PREVIOUS_OUT = Path('/tmp/toquio-fresh-final-artifacts-v1')
STUDY = Path('benchmarks/quadratic_case_study')
PRODUCER = 'ca326edbdcfed78c8fc4335069c079887d54f6c4'
ANALYSIS = '3db4e8a349adeebb62bf1f99351768072c27a3a1'
IMAGE = 'sha256:5264d4c511b47b3b8c726a9b765bf36bdf153a2e85fc2a314d149fbcb3c7ea1c'
LIMITS = {'raw-report': 1800, 'raw-plots': 900, 'pack': 21600,
          'bootstrap': 300, 'extract': 7200, 'view-report': 1800,
          'view-plots': 900, 'replay': 300}
PREREQUISITE = {'raw-report': None, 'raw-plots': 'raw-report',
                'pack': 'raw-plots', 'bootstrap': 'pack',
                'extract': 'bootstrap', 'view-report': 'extract',
                'view-plots': 'view-report', 'replay': 'view-plots'}


def stamp():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            value.update(block)
    return value.hexdigest()


def terminal_guard(root):
    if not (root/'completion.json').is_file():
        raise RuntimeError('Campaign is not terminal; no postprocessing started')
    handoff = json.loads((root/'processes/supervisor-handoff-20261015.json').read_text())
    if handoff['controller_status'] != 'campaign-terminal':
        raise RuntimeError('Controller is not terminal')
    if {p.stem for p in (root/'cells').glob('*.toml')} != set(json.loads((root/'plan.json').read_text())):
        raise RuntimeError('Incomplete or unexpected terminal coverage')
    for name in ('supervisor-conformance.json', 'resource-control-window.json',
                 'resource-control-followups.jsonl', 'cumulative-swap-evidence.json'):
        if not (root/'processes'/name).is_file():
            raise RuntimeError('Missing final control provenance: '+name)
    sys.path.insert(0, str(root/'analysis-source'/STUDY))
    from freeze_analysis import verify_analysis
    identity = verify_analysis(root)
    if identity['producing_commit'] != PRODUCER or identity['postprocessing_commit'] != ANALYSIS:
        raise RuntimeError('Unexpected producing or reporting source')
    declared = json.loads((root/'source-files.json').read_text())
    actual = {str(p.relative_to(root/'source')) for p in (root/'source').rglob('*') if p.is_file()}
    if len(declared) != 205 or actual != set(declared):
        raise RuntimeError('Producing source inventory changed')
    for name, expected in declared.items():
        if sha(root/'source'/name) != expected:
            raise RuntimeError('Producing source bytes changed')
    from packaging_conformance import compressed_allowance
    if compressed_allowance(root) != 1024**3:
        raise RuntimeError('Missing bound packaging amendment')
    return identity


def controls():
    base = Path('/sys/fs/cgroup')
    names = ('memory.max', 'memory.swap.max', 'memory.swap.current',
             'memory.current', 'memory.peak', 'cpu.max', 'memory.events')
    result = {name: (base/name).read_text().strip() for name in names}
    if result['memory.max'] != str(4*1024**3) or result['memory.swap.max'] != '0':
        raise RuntimeError('Effective memory/no-swap controls differ from intended caps')
    if result['memory.swap.current'] != '0' or result['cpu.max'] != '100000 100000':
        raise RuntimeError('Unexpected swap use or CPU control')
    return result


def execute(stage):
    root = Path('/campaign'); out = Path('/artifacts')
    started = stamp(); before = controls(); identity = terminal_guard(root)
    prior = PREREQUISITE[stage]
    if prior and not (out/(prior+'.proof.json')).is_file():
        raise RuntimeError('Missing successful prerequisite: '+prior)
    original = root/'analysis-source'/STUDY
    view = out/'view'; view_profile = view/'analysis-source'/STUDY
    detail = {}

    def run(profile, name, *args):
        subprocess.run([sys.executable, str(profile/name), *map(str, args)], check=True)

    if stage in ('raw-report', 'view-report'):
        is_view = stage == 'view-report'
        profile = view_profile if is_view else original
        report = out/('view-report' if is_view else 'raw-report')
        extra = ['--require-report-view'] if is_view else []
        run(profile, 'report.py', view if is_view else root, report, *extra)
        run(profile, 'analysis.py', report)
        if is_view:
            run(profile, 'compare.py', out/'raw-report', report)
        summary = json.loads((report/'summary.json').read_text())
        if summary['terminal_cells'] != 3132 or summary['planned_chains'] != 8640 or summary['unaudited_chains']:
            raise RuntimeError('Unexpected plan coverage or unaudited retained chains')
        if not summary['full_execution']:
            raise RuntimeError('Final report records incomplete execution; retain it for disposition before packing')
        if not is_view:
            previous = Path('/previous/raw-report')
            names = [p.relative_to(previous) for p in previous.rglob('*')
                     if p.is_file() and (p.suffix=='.csv' or len(p.relative_to(previous).parts)>1)]
            for name in names:
                if (report/name).read_bytes() != (previous/name).read_bytes():
                    raise RuntimeError('Original numerical or conformance output changed: '+str(name))
        detail = {'summary': summary, 'report_files': {p.name: sha(p) for p in report.iterdir() if p.is_file()}}
    elif stage in ('raw-plots', 'view-plots'):
        is_view = stage == 'view-plots'
        report = out/('view-report' if is_view else 'raw-report')
        run(view_profile if is_view else original, 'plots.py', report)
        names = sorted(p.name for p in report.glob('*.png'))
        if not names:
            raise RuntimeError('No actual plots generated')
        if is_view:
            if names != sorted(p.name for p in (out/'raw-report').glob('*.png')):
                raise RuntimeError('Plot inventory mismatch')
            for name in [*names, 'plot-environment.json']:
                if (report/name).read_bytes() != (out/'raw-report'/name).read_bytes():
                    raise RuntimeError('Plot or environment bytes differ: '+name)
        if not is_view:
            previous = Path('/previous/raw-report')
            if names != sorted(p.name for p in previous.glob('*.png')):
                raise RuntimeError('Original plot inventory changed')
            for name in [*names, 'plot-environment.json']:
                if (report/name).read_bytes() != (previous/name).read_bytes():
                    raise RuntimeError('Original plot bytes changed: '+name)
        detail = {'png_count': len(names), 'png_sha256': {name: sha(report/name) for name in names},
                  'raw_and_view_bytes_compared': is_view}
    elif stage == 'pack':
        run(original, 'pack.py', 'campaign', root, out/'packet')
        detail = json.loads((out/'packet/index.json').read_text())
        if detail['compressed_bytes'] > 1024**3 or detail['compressed_byte_allowance'] != 1024**3 or detail['uncompressed_bytes'] > 64*1024**3:
            raise RuntimeError('Packet exceeds frozen size allowance')
        original_inventory = json.loads((root/'processes/pre-packaging-original-byte-inventory.json').read_text())
        previous = 'analysis-history/efcc66430756a66f0ffddd58f144cfac74ac30ce/'
        for name, entry in original_inventory['files'].items():
            target = previous+name if name.startswith('analysis-source/') or name in ('analysis-files.json','postprocessing-amendment.toml') else name
            if name == 'progress.toml':
                target = 'processes/terminal-progress-before-packaging.toml'
            if detail['files'].get(target) != entry:
                raise RuntimeError('Original observed bytes not retained: '+name)
        if original_inventory['file_count'] != len(original_inventory['files']):
            raise RuntimeError('Invalid original inventory count')
        shutil.copytree(out/'raw-report', out/'packet/report')
        detail = {key: detail[key] for key in ('schema_version', 'source_commit',
                  'postprocessing_commit', 'compressed_bytes', 'uncompressed_bytes')}
    elif stage == 'bootstrap':
        run(original, 'pack.py', 'extract-analysis', out/'packet', out/'bootstrap')
    elif stage == 'extract':
        run(out/'bootstrap/analysis-source'/STUDY, 'pack.py', 'extract', out/'packet', view, '--report-view')
        detail = {'derived_view_manifest_sha256': sha(view/'extraction-view.json')}
    elif stage == 'replay':
        frozen = view/'source'/STUDY
        subprocess.run(['julia', '--startup-file=no', '--project='+str(frozen),
                        str(frozen/'replay.jl'), str(view), '6'], check=True)
        detail = {'requested_standalone_chains': 6, 'measurement_source': PRODUCER}
    proof = {'status': 'PASS', 'stage': stage, 'started_utc': started,
             'finished_utc': stamp(), 'producing_commit': identity['producing_commit'],
             'postprocessing_commit': identity['postprocessing_commit'],
             'effective_controls_before': before, 'effective_controls_after': controls(), 'detail': detail}
    path = out/(stage+'.proof.json')
    with path.open('x') as stream:
        json.dump(proof, stream, sort_keys=True, indent=2); stream.write('\n')
    print(json.dumps({'status': 'PASS', 'stage': stage, 'proof': str(path)}), flush=True)


def launch(stage):
    terminal_guard(ROOT)  # All guards precede output creation or Docker work.
    label = hashlib.sha256(str(ROOT).encode()).hexdigest()
    if subprocess.check_output(['docker', 'ps', '-q', '--filter', 'label=toquio.fresh-campaign='+label], text=True).strip():
        raise RuntimeError('A measurement worker remains live')
    prior = PREREQUISITE[stage]
    if prior and not (OUT/(prior+'.proof.json')).is_file():
        raise RuntimeError('Missing successful prerequisite: '+prior)
    if (OUT/(stage+'.proof.json')).exists():
        raise RuntimeError('Stage already succeeded; refuse redundant execution')
    OUT.mkdir(exist_ok=True)
    name = 'toquio-fresh-final-'+stage+'-v2'
    command = ['docker', 'run', '--name', name, '--memory', '4g', '--memory-swap', '4g',
               '--cpus', '1', '--network', 'none',
               '--mount', f'type=bind,src={ROOT},dst=/campaign,readonly',
               '--mount', f'type=bind,src={OUT},dst=/artifacts',
               '--mount', f'type=bind,src={PREVIOUS_OUT},dst=/previous,readonly',
               '--mount', f'type=bind,src={Path(__file__).resolve()},dst=/stage.py,readonly',
               '--mount', 'type=bind,src=/home/bernalde/.local/bin/uv,dst=/usr/local/bin/uv,readonly',
               '--mount', 'type=volume,src=toquio-fresh-python-env,dst=/python',
               '--mount', 'type=volume,src=toquio-dell-study-depot,dst=/depot',
               '--env', 'UV_CACHE_DIR=/python/cache', '--env', 'UV_PYTHON_INSTALL_DIR=/python/managed',
               '--env', 'PYTHONDONTWRITEBYTECODE=1', '--env', 'OPENBLAS_NUM_THREADS=1',
               '--env', 'JULIA_DEPOT_PATH=/depot', '--env', 'JULIA_NUM_THREADS=1',
               '--env', 'JULIA_NUM_PRECOMPILE_TASKS=1', IMAGE,
               'timeout', '--kill-after=30', str(LIMITS[stage]),
               'uv', 'run', '--offline', '--no-project', '--python', '3.13.5']
    if stage.endswith('plots'):
        command += ['--with-requirements', '/campaign/analysis-source/'+str(STUDY/'plot-lock.txt')]
    command += ['python', '/stage.py', stage, '--inside']
    log = OUT/(stage+'.log')
    with log.open('xb') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    print(json.dumps({'stage': stage, 'exit_code': result.returncode, 'log': str(log)}))
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=LIMITS)
    parser.add_argument('--inside', action='store_true')
    args = parser.parse_args()
    execute(args.stage) if args.inside else launch(args.stage)
