"""Qualify watchdog gaps independently of memory/swap conformance.

The manifest binds the exact recovery observations and executed controller
sources. Associations use the union of recorded gaps, not their bounding span.
"""
import datetime as dt
import json
import tomllib
from pathlib import Path
from resource_conformance import build, digest, utc


def checked_file(root, name):
    path = Path(name)
    if (path.parent != Path('processes') or (root/path).is_symlink() or
            not (root/path).is_file() or (root/path).stat().st_size > 65536):
        raise ValueError('Invalid supervision provenance file')
    return root/path


def attach(root, output):
    manifest = root/'processes/supervisor-conformance.json'
    observations = {str(p.relative_to(root)) for pattern in
                    ('supervisor-recovery-*.json', 'supervisor-handoff-*.json')
                    for p in (root/'processes').glob(pattern)}
    if not manifest.exists():
        if observations:
            raise ValueError('Supervision recovery is missing its provenance manifest')
        if (output/'supervision-conformance').exists():
            raise ValueError('Existing report has supervision provenance absent from this campaign')
        return None
    checked_file(root, 'processes/supervisor-conformance.json')
    record = json.loads(manifest.read_text())
    run = tomllib.loads((root/'run.toml').read_text())
    if (record['schema_version'] != 1 or record['source_commit'] != run['source_commit'] or
            not isinstance(record['window_basis'], str) or not record['window_basis'].strip()):
        raise ValueError('Invalid supervision provenance identity or window basis')
    entries = record['recoveries']
    if not entries or {entry['file'] for entry in entries} != observations or len(entries) != len(observations):
        raise ValueError('Unexpected supervision recovery inventory')
    controllers = record['controllers']
    if not controllers or len({entry['file'] for entry in controllers}) != len(controllers):
        raise ValueError('Unexpected supervision controller inventory')
    controller_hashes = {}
    for entry in controllers:
        path = checked_file(root, entry['file'])
        if not path.name.endswith('.py') or digest(path) != entry['sha256']:
            raise ValueError('Changed executed supervision controller')
        controller_hashes[entry['file']] = entry['sha256']
    ledgers = [json.loads(p.read_text()) for p in (root/'processes').glob('[0-9][0-9][0-9][0-9].json')]
    windows = []
    recovery_hashes = {entry['file']: entry['sha256'] for entry in entries}
    for entry in entries:
        path = checked_file(root, entry['file'])
        if digest(path) != entry['sha256']:
            raise ValueError('Changed supervision recovery observation')
        event = json.loads(path.read_text())
        if (event['schema_version'] != 1 or event['source_commit'] != run['source_commit'] or
                event['original_container'] != record['original_container'] or
                event['original_container_id'] != record['original_container_id'] or
                not any(p['container'] == event['original_container'] for p in ledgers) or
                controller_hashes.get(entry['controller_source_file']) != entry['controller_source_sha256']):
            raise ValueError('Supervision recovery identity mismatch')
        if any(event[key] is not False for key in ('worker_restarted', 'measurement_reruns',
                'measurement_source_changed', 'statistical_protocol_changed')):
            raise ValueError('Unsupported supervision recovery disposition')
        beginning, finish = event['conservative_gap_start_utc'], event['supervision_restored_utc']
        if event['kind'] == 'interrupted-host-supervisor-recovery':
            prior = dt.datetime.strptime(event['last_confirmed_supervision_utc_approx'],
                                         '%Y-%m-%d %H:%M UTC').replace(tzinfo=dt.timezone.utc)
            latest_start = prior-dt.timedelta(minutes=1)
        elif event['kind'] == 'controlled-supervisor-handoff':
            latest_start = utc(event['last_confirmed_supervision_utc_approx'])
            if (recovery_hashes.get(event['prior_recovery_record']) != event['prior_recovery_sha256'] or
                    controller_hashes.get(event['prior_controller_source']) != event['prior_controller_sha256'] or
                    entry['controller_source_file'] != event['controller_source'] or
                    entry['controller_source_sha256'] != event['controller_sha256']):
                raise ValueError('Changed supervision handoff provenance')
        else:
            raise ValueError('Unsupported supervision recovery kind')
        if (utc(beginning) > latest_start or utc(beginning) >= utc(finish) or
                utc(event['active_phase_utc']) > utc(finish)):
            raise ValueError('Supervision window does not bound recorded observations')
        windows.append(dict(start=beginning, end=finish, active_cell=event['active_cell'],
                            recovery_file=entry['file']))
    start = min((w['start'] for w in windows), key=utc)
    end = max((w['end'] for w in windows), key=utc)
    return build(root, manifest, output/'supervision-conformance', start, end,
                 window_basis=record['window_basis'], window_sha256=digest(manifest),
                 active_cell=windows[0]['active_cell'], windows=windows,
                 prefix='supervision-conformance', field='supervision_qualification',
                 label='continuous-watchdog-enforcement-uncertain',
                 evidence_key='provenance_manifest_sha256',
                 conformance='Continuous host phase/campaign deadline enforcement cannot be certified during the recorded gaps')
