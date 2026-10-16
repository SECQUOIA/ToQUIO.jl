#!/usr/bin/env python3
"""Verify a retained campaign and regenerate tables without solving or sampling."""
from __future__ import annotations
import argparse, csv, hashlib, json, math, re, statistics, tomllib
from collections import Counter, defaultdict
from pathlib import Path
from campaign import digest, read_toml, planned_ids, verify_inputs

ARMS = ('native', 'radix4', 'bounded4-cap64', 'binary-radix2',
        'toqubo-controlled-binary', 'toqubo-default-binary')

def source_objective(source, point):
    return (math.fsum(a * x for a, x in zip(source['linear'], point)) +
            math.fsum(a * point[i] * point[j] for i, row in enumerate(source['quadratic_rows'])
                      for j, a in enumerate(row)))

def feasible(source, point):
    if len(point) != len(source['lower']): return False
    if not all(isinstance(x, int) and l <= x <= u for l, x, u in
               zip(source['lower'], point, source['upper'])): return False
    for terms, relation, bound in zip(source['rows'], source['relations'], source['rhs']):
        value = sum(a * point[i-1] for i, a in terms)
        if not (value == bound if relation == 'eq' else value <= bound): return False
    return True

CELL_LINE_LIMIT = 8 * 1024**2
CELL_VIEW_LIMIT = 16 * 1024**2
CELL_HEADER = re.compile(rb'\[\[?([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*)\]\]?\s*')


def bounded_cell_lines(stream):
    while line := stream.readline(CELL_LINE_LIMIT + 1):
        if len(line) > CELL_LINE_LIMIT:
            raise ValueError('Cell record line exceeds bounded reader allowance')
        yield line


def projected_cell_bytes(lines):
    """Omit only unused compiler.metadata tables from producer-format TOML bytes."""
    skipped = False; size = 0
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith(b'['):
            header = CELL_HEADER.fullmatch(stripped)
            if header:
                name = header.group(1)
                skipped = name == b'compiler.metadata' or name.startswith(b'compiler.metadata.')
        if not skipped:
            size += len(line)
            if size > CELL_VIEW_LIMIT:
                raise ValueError('Report cell fields exceed bounded reader allowance')
            yield line


def read_cell_record(path):
    # The packet retains every original byte; this projection only bounds memory.
    with open(path, 'rb') as stream:
        return tomllib.loads(b''.join(projected_cell_bytes(bounded_cell_lines(stream))).decode('utf-8'))

def verify(root, *, allow_incomplete=False, require_report_view=False):
    from packet_io import verify_report_view
    verify_report_view(root, required=require_report_view)
    run = read_toml(root / 'run.toml'); snapshot = root / 'source'
    if (root / 'analysis-files.json').exists():
        from freeze_analysis import verify_analysis
        verify_analysis(root)
    files = json.loads((root / 'source-files.json').read_text())
    for relative, expected in files.items():
        if digest(snapshot / relative) != expected: raise ValueError(f'Changed execution source: {relative}')
    protocol = read_toml(snapshot / 'benchmarks/quadratic_case_study/protocol.toml')
    if digest(snapshot / 'benchmarks/quadratic_case_study/protocol.toml') != run['protocol_sha256']:
        raise ValueError('Protocol identity mismatch')
    verify_inputs(snapshot, root / 'inputs')
    inventory = read_toml(root / 'inputs/inventory.toml')['instances']
    planned = planned_ids(inventory, protocol['arms'])
    if json.loads((root / 'plan.json').read_text()) != planned: raise ValueError('Plan mismatch')
    sources = {}
    for entry in inventory:
        path = root / 'inputs' / entry['file']
        if digest(path) != entry['sha256']: raise ValueError('Input hash mismatch')
        sources[entry['instance_id']] = read_toml(path)
    records = {}
    for path in sorted((root / 'cells').glob('*.toml')):
        record = read_cell_record(path); identifier = path.stem
        if identifier not in planned or record['cell_id'] != identifier: raise ValueError('Unexpected cell')
        expected = planned[identifier]
        if any(record[key] != value for key, value in expected.items()): raise ValueError('Cell identity mismatch')
        if record['source_commit'] != run['source_commit'] or record['protocol_sha256'] != run['protocol_sha256']:
            raise ValueError('Stale result identity')
        if record['status'] == 'measured' and record['kind'] == 'direct':
            result = record['result']; source = sources[record['instance_id']]
            if result['source_feasible']:
                point = result['rounded_point']
                if not feasible(source, point): raise ValueError('Direct source infeasible')
                objective = source_objective(source, point)
                if not math.isclose(objective, result['source_objective'], rel_tol=1e-12, abs_tol=1e-9):
                    raise ValueError('Direct source objective mismatch')
            if result['backend'] != run['backend']: raise ValueError('Mixed baseline backend')
        # The raw packet retains these diagnostics; tables do not consume them.
        for key in ('maps', 'penalties', 'verification'):
            record.pop(key, None)
        if 'metrics' in record: record['metrics'].pop('eigenvalues', None)
        records[identifier] = record
    if not allow_incomplete and set(records) != set(planned): raise ValueError('Missing cells')
    chains = []; unaudited = []; slots = set()
    polynomials = {}
    for path in sorted((root / 'chains').glob('*.toml')):
        chain = read_toml(path); identifier = chain['instance_id']; source = sources[identifier]
        base = f'{identifier}--{chain["arm"]}'
        expected_name = f'{base}--b{chain["batch"]}-r{chain["read"]}'
        if path.stem != expected_name or base not in planned: raise ValueError('Unexpected chain identity')
        if not (1 <= chain['batch'] <= 3 and 1 <= chain['read'] <= 10): raise ValueError('Unexpected chain slot')
        if chain['source_hash'] != planned[base]['source_hash']: raise ValueError('Stale chain source')
        if chain['reserved_proposals'] != 4000 or not 0 <= chain['completed_proposals'] <= 4000:
            raise ValueError('Invalid chain work reservation')
        moves = chain['move_counts']
        if moves['boundary'] + moves['accepted'] + moves['energy_rejected'] != chain['completed_proposals']:
            raise ValueError('Invalid move totals')
        slot = (identifier, chain['arm'], chain['batch'], chain['read'])
        if slot in slots: raise ValueError('Duplicate chain slot')
        slots.add(slot)
        if chain['max_seconds'] != 2.0 or chain['temperature_start'] != 2.0 or chain['temperature_end'] != 0.01:
            raise ValueError('Unexpected sampler settings')
        if chain['source_observations'] != chain['completed_proposals'] + 1: raise ValueError('Observation total mismatch')
        poly_path = root / 'polynomials' / (base + '.toml')
        if base not in polynomials: polynomials[base] = read_toml(poly_path)
        archived = polynomials[base]; polynomial = archived['polynomial']; maps = archived['maps']
        def decode(point):
            if len(point) != len(polynomial['lower']) or not all(isinstance(v,int) and l<=v<=u
                    for l,v,u in zip(polynomial['lower'],point,polynomial['upper'])):
                raise ValueError('Invalid retained target state')
            return [m['offset'] + sum(w*point[j-1] for j,w in zip(m['positions'],m['weights']))
                    for m in maps[:len(source['lower'])]]
        decode(chain['initial'])
        if decode(chain['final']) != chain['terminal_source']: raise ValueError('Terminal projection mismatch')
        for sample in chain['samples']:
            point = decode(sample['state'])
            if point != sample['source'] or feasible(source,point) != sample['source_feasible']:
                raise ValueError('RLE source projection/feasibility mismatch')
            if not math.isclose(source_objective(source,point),sample['source_objective'],rel_tol=1e-12,abs_tol=1e-9):
                raise ValueError('RLE objective mismatch')
        if chain['any_feasible'] != (chain['first_feasible_proposal'] != 'missing'):
            raise ValueError('First-feasible event mismatch')
        if not math.isfinite(chain['elapsed_seconds']) or chain['elapsed_seconds'] < 0: raise ValueError('Invalid elapsed time')
        if chain['any_feasible']:
            best = chain['best_feasible_source']
            if not feasible(source,best) or not math.isclose(source_objective(source,best),
                    chain['best_feasible_objective'],rel_tol=1e-12,abs_tol=1e-9):
                raise ValueError('Best-visited source/objective mismatch')
            if not (0 <= chain['first_feasible_proposal'] <= chain['completed_proposals']):
                raise ValueError('First-feasible work outside chain')
            first = chain['first_feasible_seconds']
            if not isinstance(first,(int,float)) or not math.isfinite(first) or not 0<=first<=chain['elapsed_seconds']:
                raise ValueError('First-feasible measured time outside chain')
        elif chain['best_feasible_objective'] != 'missing' or chain['first_feasible_seconds'] != 'missing':
            raise ValueError('No-hit chain retained a success statistic')
        audit_path = root / 'replay-audits' / path.name
        if not audit_path.exists():
            unaudited.append(path.name)
            continue
        audit = read_toml(audit_path)
        expected_audit = dict(chain_sha256=digest(path), polynomial_file_sha256=digest(poly_path),
            input_file_sha256=planned[base]['source_hash'], source_commit=run['source_commit'],
            protocol_sha256=run['protocol_sha256'], julia_version='1.10.11', replay_result='pass')
        if any(audit.get(k) != value for k,value in expected_audit.items()): raise ValueError('Replay evidence binding mismatch')
        cell = records.get(base,{})
        if cell.get('status') == 'measured':
            metrics = cell['metrics']
            if (chain['polynomial_sha256'] != metrics['raw_polynomial_sha256'] or
                    chain['source_projection_sha256'] != metrics['source_projection_sha256']):
                raise ValueError('Chain/compiled mapping identity mismatch')
        valid = feasible(source, chain['terminal_source'])
        if valid != chain['terminal_source_feasible']: raise ValueError('Terminal feasibility mismatch')
        objective = source_objective(source, chain['terminal_source'])
        if not math.isclose(objective, chain['terminal_source_objective'], rel_tol=1e-12, abs_tol=1e-9):
            raise ValueError('Terminal objective mismatch')
        if chain['first_feasible_censored'] != (chain['first_feasible_proposal'] == 'missing'):
            raise ValueError('Invalid first-feasible censoring')
        chains.append(chain)
    for identifier,record in records.items():
        if record['kind']=='structural' and record['status']=='measured' and sources[record['instance_id']]['family']=='knapsack':
            expected={(record['instance_id'],record['arm'],b,r) for b in range(1,4) for r in range(1,11)}
            verified={(c['instance_id'],c['arm'],c['batch'],c['read']) for c in chains}
            if not expected <= verified: raise ValueError('Measured knapsack cell lacks its 30 audited chains')
    return run, protocol, inventory, records, chains, unaudited

def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    keys = sorted({key for row in rows for key in row})
    with open(path, 'w', newline='') as target:
        writer = csv.DictWriter(target, fieldnames=keys); writer.writeheader(); writer.writerows(rows)

def aggregate(root, output, *, allow_incomplete=False, require_report_view=False):
    run, protocol, inventory, records, chains, unaudited = verify(root, allow_incomplete=allow_incomplete, require_report_view=require_report_view)
    from resource_conformance import attach
    qualification = attach(root, output)
    from supervision_conformance import attach as attach_supervision
    supervision = attach_supervision(root, output)
    from packaging_conformance import qualification as packaging_qualification
    packaging = packaging_qualification(root)
    entries = {row['instance_id']: row for row in inventory}
    structural = []; direct = []
    plan=json.loads((root/'plan.json').read_text())
    for identifier,expected in plan.items():
        record=records.get(identifier,dict(expected,cell_id=identifier,status='not-started'))
        entry = entries[record['instance_id']]
        common = {key: entry[key] for key in ('instance_id', 'family', 'profile', 'n', 'm', 'replicate')}
        common.update(status=record['status'], source_hash=record['source_hash'])
        if record['kind'] == 'structural':
            common['arm'] = record['arm']
            if record['status'] == 'measured':
                common.update({k: v for k, v in record['metrics'].items() if not isinstance(v, (list, dict))})
                common.update({k: record['compiler'][k] for k in
                               ('construction_seconds', 'full_conversion_seconds', 'compilation_seconds',
                                'extraction_seconds', 'compilation_allocated_bytes')})
            structural.append(common)
        else:
            if record['status'] == 'measured':
                common.update({k: v for k, v in record['result'].items() if not isinstance(v, (list, dict))})
            direct.append(common)
    write_csv(output / 'structural.csv', structural); write_csv(output / 'direct.csv', direct)
    batch_groups = defaultdict(list)
    for chain in chains: batch_groups[(chain['instance_id'], chain['arm'], chain['batch'])].append(chain)
    batches = []
    for entry in inventory:
        if entry['family']=='knapsack':
            for arm in ARMS:
                for batch in range(1,4): batch_groups.setdefault((entry['instance_id'],arm,batch),[])
    for (identifier, arm, batch), group in sorted(batch_groups.items()):
        entry = entries[identifier]; reference = records.get(identifier + '--direct', {})
        result = reference.get('result', {})
        feasible_reads = [chain['terminal_source_objective'] for chain in group if chain['terminal_source_feasible']]
        best = max(feasible_reads, default=None); ref = result.get('source_objective') if result.get('source_feasible') else None
        events = [chain['first_feasible_seconds'] for chain in group if not chain['first_feasible_censored']]
        best_visited = [chain['best_feasible_objective'] for chain in group if chain['any_feasible']]
        row = {key: entry[key] for key in ('instance_id', 'n', 'm', 'replicate')}
        row.update(arm=arm, batch=batch, planned_reads=10, completed_reads=len(group),
            missing_or_unaudited_reads=10-len(group),
            feasible_terminal_reads=len(feasible_reads),
            terminal_feasible_frequency=len(feasible_reads)/len(group) if group else None,
            feasible_over_planned_lower_bound=len(feasible_reads)/10,
            any_hit_chains=sum(chain['any_feasible'] for chain in group),
            no_hit_censored_chains=sum(chain['first_feasible_censored'] for chain in group),
            elapsed_seconds=sum(chain['elapsed_seconds'] for chain in group),
            completed_proposals=sum(chain['completed_proposals'] for chain in group),
            reserved_proposals=40000, best_terminal_source_objective=best,
            best_visited_source_objective=max(best_visited, default=None),
            median_first_feasible_seconds_conditional_on_hit=statistics.median(events) if events else None,
            reference_objective=ref, reference_termination=result.get('termination', 'missing'),
            reference_kind=('numerically-global-optimal' if result.get('termination') == 'OPTIMAL' else 'incumbent')
                if ref is not None else 'unavailable',
            sense_aware_terminal_relative_gap=(ref-best)/max(1,abs(ref)) if ref is not None and best is not None else None,
            terminal_objective_ratio=best/ref if ref not in (None,0) and best is not None else None)
        batches.append(row)
    write_csv(output / 'knapsack-batches.csv', batches)
    paired = []
    native = {row['instance_id']: row for row in structural if row['arm'] == 'native' and row['status'] == 'measured'}
    for row in structural:
        base = native.get(row['instance_id'])
        if not base or row['status'] != 'measured': continue
        paired.append(dict(instance_id=row['instance_id'], family=row['family'], profile=row['profile'], arm=row['arm'],
            active_variable_change=row['active_variables']-base['active_variables'],
            coefficient_ratio_change=(row['coefficient_ratio']-base['coefficient_ratio'])
                if isinstance(row['coefficient_ratio'], (int,float)) and isinstance(base['coefficient_ratio'], (int,float)) else '',
            conversion_seconds_change=row['full_conversion_seconds']-base['full_conversion_seconds'],
            exact_polynomial_alias=row['canonical_polynomial_sha256']==base['canonical_polynomial_sha256'],
            exact_projection_alias=row['source_projection_sha256']==base['source_projection_sha256']))
    write_csv(output / 'paired-to-native.csv', paired)
    counts = Counter(row['status'] for row in records.values())
    summary = dict(source_commit=run['source_commit'], protocol_sha256=run['protocol_sha256'],
        source_profiles=len(inventory), planned_structural=2736, planned_direct=396, planned_chains=8640,
        terminal_cells=len(records), cell_statuses=dict(sorted(counts.items())),
        retained_chains=len(chains)+len(unaudited), verified_chains=len(chains), unaudited_chains=len(unaudited),
        source_witness_statuses=dict(sorted(Counter(read_toml(root/"inputs"/e["file"]).get("witness_status","unspecified-validation-fixture")
            for e in inventory).items())),
        completed_proposals=sum(row['completed_proposals'] for row in chains),
        reserved_proposals=34560000, physical_provider='pending-no-jobs',
        full_execution=(len(records)==3132 and counts.get('measured',0)==3132 and len(chains)==8640 and not unaudited))
    output.mkdir(parents=True, exist_ok=True)
    if qualification is not None:
        summary['resource_conformance'] = qualification
    if supervision is not None:
        summary['supervision_conformance'] = supervision
    if packaging is not None:
        summary['packaging_conformance'] = packaging
    (output / 'summary.json').write_text(json.dumps(summary,sort_keys=True,indent=2)+'\n')
    return summary, structural, direct, batches

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--allow-incomplete',action='store_true')
    parser.add_argument('--require-report-view',action='store_true')
    args=parser.parse_args()
    summary,*_=aggregate(args.campaign,args.output,allow_incomplete=args.allow_incomplete,
        require_report_view=args.require_report_view)
    print(json.dumps(summary,sort_keys=True))
