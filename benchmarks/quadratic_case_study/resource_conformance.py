"""Associate one recorded resource deviation with immutable measurement intervals.

Cell UTC intervals bound their chains conservatively; no chain UTC is inferred
from its measured elapsed time. This tool changes no raw measurement or status.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import re
import tomllib
from pathlib import Path


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1024**2):
            h.update(block)
    return h.hexdigest()


def utc(value):
    parsed = dt.datetime.fromisoformat(value)
    return (parsed.replace(tzinfo=dt.timezone.utc) if parsed.tzinfo is None
            else parsed.astimezone(dt.timezone.utc))


def scalar_header(path):
    lines = []
    with path.open('rb') as stream:
        while line := stream.readline(65537):
            if len(line) > 65536 or sum(map(len, lines)) + len(line) > 65536:
                raise ValueError('Unexpected cell scalar-header size')
            if line.lstrip().startswith(b'['):
                break
            lines.append(line)
    raw = b''.join(lines)
    return tomllib.loads(raw.decode()), hashlib.sha256(raw).hexdigest()


def qualification(start, finish, window_start, window_end, *, terminal):
    if start and finish and utc(finish) < utc(start):
        raise ValueError('Reversed cell interval')
    if start and utc(start) > window_end:
        return False, 'outside-recorded-uncertainty-window'
    if finish and utc(finish) < window_start:
        return False, 'outside-recorded-uncertainty-window'
    if not start and not terminal:
        return None, 'not-yet-measured'
    return True, ('effective-swap-limit-uncertain' if start and finish
                  else 'potential-overlap-missing-boundary')


def write_csv(path, rows, fields):
    temporary = path.with_name(path.name+'.tmp')
    with temporary.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def build(root, incident, output, start, end, *, window_basis, window_sha256, active_cell):
    if utc(start) >= utc(end):
        raise ValueError('Empty uncertainty window')
    plan = json.loads((root/'plan.json').read_text())
    terminal = {p.stem: p for p in (root/'cells').glob('*.toml')}
    if not set(terminal) <= set(plan):
        raise ValueError('Unplanned cell')
    cells = []
    by_id = {}
    for identifier, planned in sorted(plan.items()):
        if Path(identifier).name != identifier:
            raise ValueError('Unsafe cell identity')
        marker = root/'attempts'/(identifier+'.toml')
        attempt = tomllib.loads(marker.read_text()) if marker.exists() else {}
        if attempt and attempt['cell_id'] != identifier:
            raise ValueError('Attempt identity mismatch')
        header, header_hash = scalar_header(terminal[identifier]) if identifier in terminal else ({}, '')
        if header and header['cell_id'] != identifier:
            raise ValueError('Terminal identity mismatch')
        beginning = attempt.get('started_utc', '')
        finish = header.get('finished_utc', '')
        overlap, status = qualification(beginning, finish, utc(start), utc(end),
                                        terminal=identifier in terminal)
        row = dict(cell_id=identifier, kind=planned['kind'],
                   raw_status=header.get('status', 'not-terminal'),
                   started_utc=beginning, finished_utc=finish,
                   potential_overlap='' if overlap is None else str(overlap).lower(),
                   resource_qualification=status,
                   attempt_sha256=digest(marker) if marker.exists() else '',
                   terminal_scalar_header_sha256=header_hash)
        cells.append(row)
        by_id[identifier] = row
    if active_cell not in by_id or by_id[active_cell]['potential_overlap'] != 'true':
        raise ValueError('Resource window excludes the incident active cell')
    chains = []
    for path in sorted((root/'chains').glob('*.toml')):
        match = re.fullmatch(r'(.+)--b([1-3])-r(10|[1-9])', path.stem)
        if not match or match[1] not in by_id:
            raise ValueError('Unplanned chain identity')
        parent = by_id[match[1]]
        chains.append(dict(chain_id=path.stem, parent_cell_id=match[1],
                           interval_basis='conservative-parent-cell-UTC-interval',
                           started_utc=parent['started_utc'], finished_utc=parent['finished_utc'],
                           potential_overlap=parent['potential_overlap'],
                           resource_qualification=parent['resource_qualification'],
                           raw_chain_sha256=digest(path)))
    summary = dict(schema_version=1, incident_sha256=digest(incident),
                   generator_sha256=digest(Path(__file__)),
                   uncertainty_window_start_utc=start, uncertainty_window_end_utc=end,
                   interval_boundary='closed; UTC; parent intervals conservatively bound chains',
                   window_basis=window_basis, window_record_sha256=window_sha256,
                   planned_cells=len(plan), terminal_cells=len(terminal), retained_chains=len(chains),
                   overlapping_cells=sum(r['potential_overlap']=='true' for r in cells),
                   overlapping_chains=sum(r['potential_overlap']=='true' for r in chains),
                   campaign_terminal=(root/'completion.json').exists(),
                   measurement_values_changed=False,
                   qualification_scope='This incident only; outside-window does not certify other resource properties',
                   conformance='Effective no-swap enforcement cannot be certified throughout the uncertainty window')
    if output.is_symlink():
        raise ValueError('Unexpected resource report link')
    output.mkdir(parents=True, exist_ok=True)
    names = ['resource-conformance-'+name for name in ('cells.csv','chains.csv','summary.json')]
    if any((output/name).is_symlink() or (output/(name+'.tmp')).is_symlink() for name in names):
        raise ValueError('Unexpected resource report file link')
    write_csv(output/'resource-conformance-cells.csv', cells, list(cells[0]))
    write_csv(output/'resource-conformance-chains.csv', chains, list(chains[0]) if chains else
              ['chain_id','parent_cell_id','interval_basis','started_utc','finished_utc',
               'potential_overlap','resource_qualification','raw_chain_sha256'])
    temporary = output/'resource-conformance-summary.json.tmp'
    temporary.write_text(json.dumps(summary, sort_keys=True, indent=2)+'\n')
    temporary.replace(output/'resource-conformance-summary.json')
    return summary


def attach(root, output):
    """Require a bound window for any retained deviation; rebuild its associations."""
    window = root/'processes/resource-control-window.json'
    incidents = {str(p.relative_to(root)) for p in
                 (root/'processes').glob('resource-control-observation-*.json')}
    if not window.exists():
        if incidents:
            raise ValueError('Resource deviation is missing its uncertainty window')
        if (output/'resource-conformance').exists():
            raise ValueError('Existing report has resource provenance absent from this campaign')
        return None
    if window.is_symlink() or window.stat().st_size > 65536:
        raise ValueError('Invalid resource uncertainty window')
    record = json.loads(window.read_text())
    name = record['incident_file']
    if (record['schema_version'] != 1 or incidents != {name} or
            Path(name).parent != Path('processes') or (root/name).is_symlink() or
            (root/name).stat().st_size > 65536):
        raise ValueError('Unexpected resource incident inventory')
    run = tomllib.loads((root/'run.toml').read_text())
    incident = json.loads((root/name).read_text())
    if (digest(root/name) != record['incident_sha256'] or
            record['source_commit'] != run['source_commit'] or
            incident['source_commit'] != run['source_commit']):
        raise ValueError('Resource incident identity mismatch')
    prior = incident['prior_observation']
    prior_utc = dt.datetime.strptime(prior['utc_approx'], '%Y-%m-%d %H:%M UTC').replace(tzinfo=dt.timezone.utc)
    if (prior['memory_swap_max'] != '0' or incident['kernel_after']['memory_swap_max'] != '0' or
            not isinstance(record['window_basis'], str) or not record['window_basis'].strip() or
            utc(record['window_start_utc']) > prior_utc-dt.timedelta(minutes=1) or
            utc(record['window_end_utc']) < utc(incident['recorded_at_utc'])):
        raise ValueError('Resource window does not bound the recorded observations')
    return build(root, root/name, output/'resource-conformance',
                 record['window_start_utc'], record['window_end_utc'],
                 window_basis=record['window_basis'], window_sha256=digest(window),
                 active_cell=incident['active_cell'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(attach(args.campaign, args.output), sort_keys=True))
