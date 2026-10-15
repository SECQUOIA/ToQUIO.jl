#!/usr/bin/env python3
"""Rebuild a descriptive Markdown report from the verified CSV tables."""
import argparse,csv,json,math,statistics
from collections import Counter
from pathlib import Path
from report import ARMS

def rows(path):
    with open(path,newline='') as source:return list(csv.DictReader(source))

def numeric(value):
    try:return float(value)
    except (ValueError,TypeError):return None

def median(values):
    values=[x for x in values if x is not None and math.isfinite(x)]
    return 'undefined' if not values else f'{statistics.median(values):.5g}'

def render(directory):
    summary=json.loads((directory/'summary.json').read_text())
    structure=rows(directory/'structural.csv');direct=rows(directory/'direct.csv')
    batches=rows(directory/'knapsack-batches.csv');pairs=rows(directory/'paired-to-native.csv')
    lines=['# Fresh quadratic case study','',
        'This report uses fresh synthetic instances and current exact integer encodings. '
        'It reports local software experiments; physical-provider replication remains pending.','',
        f"Executable source: `{summary['source_commit']}`. Protocol SHA-256: `{summary['protocol_sha256']}`.",'',
        f"Coverage: {summary['source_profiles']} source profiles; {summary['terminal_cells']} terminal cells "
        f"of 3,132 planned (2,736 structural and 396 direct). Statuses: `{summary['cell_statuses']}`. "
        f"Verified chains: {summary['verified_chains']}/8,640; unaudited: {summary['unaudited_chains']}. "
        f"Completed proposals: {summary['completed_proposals']:,} of 34,560,000 reserved.",'',
        ('All planned software cells were measured and all planned chains retained and verified.'
         if summary['full_execution'] else
         '**Execution is incomplete.** Missing, refused, errored and censored cells remain part of the study; '
         'the available measurements do not establish full execution.'),'',
        'Source feasibility screens/witnesses: `'+str(summary.get('source_witness_statuses',{}))+'`. '
        'Capacity-infeasible facility draws are retained without replacement; they have no source optimum.', '',
        '## Structural comparisons','',
        'Rows pool the stated grids and three fresh draws within each profile. Medians are descriptive; '
        'a single compilation per cell does not establish statistically significant speedups. '
        'Conversion includes all applicable compiler stages and extraction; source construction is separate. '
        'Density uses active unordered couplers, and coefficient ratios use canonical nonzero coefficients. '
        'A lower variable count or coefficient ratio alone does not prove better optimization performance.','']
    for family in ('facility','inventory','route_allocation','knapsack'):
        for profile in sorted({r['profile'] for r in structure if r['family']==family}):
            lines += [f'### {family}: {profile}','',
                '| Arm | Measured / planned | Median active variables | Median density | Median conversion s | Median coefficient ratio |',
                '|---|---:|---:|---:|---:|---:|']
            for arm in ARMS:
                allrows=[r for r in structure if r['family']==family and r['profile']==profile and r['arm']==arm]
                good=[r for r in allrows if r['status']=='measured']
                fields=[median([numeric(r.get(key)) for r in good]) for key in
                    ('active_variables','density','full_conversion_seconds','coefficient_ratio')]
                lines.append(f'| {arm} | {len(good)} / {len(allrows)} | '+' | '.join(fields)+' |')
            lines += ['',f'![Structural comparison]({family}-{profile}-structure.png)','']
    lines += ['## Paired changes from native','',
        'Each change is computed within the same source profile before aggregation. Positive variable '
        'changes mean more target variables. The default ToQUBO arm also changes penalty/GCD policy. '
        'Exact polynomial aliases are identified by the same canonical polynomial/domain hash; source '
        'projection identity is checked separately.','',
        '| Arm | Measured pairs | Median active-variable change | Median conversion-time change s | Exact canonical aliases |',
        '|---|---:|---:|---:|---:|']
    for arm in ARMS:
        selected=[r for r in pairs if r['arm']==arm]
        lines.append(f'| {arm} | {len(selected)} | '+
            median([numeric(r['active_variable_change']) for r in selected])+' | '+
            median([numeric(r['conversion_seconds_change']) for r in selected])+' | '+
            str(sum(r['exact_polynomial_alias']=='True' for r in selected))+' |')
    lines += ['', '## Original-source solver references','',
        'The direct model is the original constrained integer quadratic problem. '
        'Numerical global solver optimality is distinct from exact exhaustive proof. '
        'Interrupted incumbents remain labeled as incumbents. The nonnegative route allocation model '
        'has an independent monotonicity certificate in both coefficient profiles.','',
        '| Family / profile | Retained cases | Solver termination counts | Independently feasible primals |',
        '|---|---:|---|---:|']
    for key in sorted({(r['family'],r['profile']) for r in direct}):
        selected=[r for r in direct if (r['family'],r['profile'])==key]
        status=Counter(r.get('termination') or r['status'] for r in selected)
        lines.append(f"| {' / '.join(key)} | {len(selected)} | {dict(sorted(status.items()))} | "+
            str(sum(r.get('source_feasible')=='True' for r in selected))+' |')
    lines += ['', '## Local knapsack sampling','',
        'Primary quality uses the best source-feasible **terminal independent read** per batch. '
        'Best-visited diagnostics and any-hit chains are separate. Every planned ten-read batch appears, '
        'including empty or interrupted batches. Observed feasibility divides by verified completed reads; '
        'missing reads are not failures. An incumbent-relative ratio may exceed one. '
        'First-feasible wall time is measured and hash-bound; proposal decisions and first-feasible work '
        'are replayed. No IID time-to-success estimate is inferred from correlated chain observations.','',
        '| Arm | Verified / planned reads | Feasible terminal reads / verified | Missing or unaudited | Batches with feasible terminal / planned | Median gap, numerically optimal references |',
        '|---|---:|---:|---:|---:|---:|']
    for arm in ARMS:
        selected=[r for r in batches if r['arm']==arm]
        completed=sum(int(r['completed_reads']) for r in selected)
        feasible=sum(int(r['feasible_terminal_reads']) for r in selected)
        quality=[numeric(r['sense_aware_terminal_relative_gap']) for r in selected
                 if r['reference_kind']=='numerically-global-optimal']
        lines.append(f'| {arm} | {completed} / {10*len(selected)} | {feasible} / {completed} | '+
            str(sum(int(r['missing_or_unaudited_reads']) for r in selected))+' | '+
            f"{sum(bool(r['best_terminal_source_objective']) for r in selected)} / {len(selected)} | "+median(quality)+' |')
    lines += ['', '![Local knapsack quality](knapsack-quality-pooled.png)','',
        'Per-replicate quality and observed first-feasibility/censoring plots accompany the raw tables.','',
        '## Mathematical and numerical limits','',
        'Exact affine interval coverage is checked for every compiled target. Independent exhaustive '
        'manufactured source/target fixtures establish optimum correspondence for integer/dyadic test '
        'cases. Three large-target Float64 energy checks are diagnostics rather than exhaustive proofs. '
        'Feasible-witness cancellation errors are retained in raw verification records; sufficient '
        'mathematical penalties do not eliminate floating-point rounding. A finite-budget sampler miss '
        'does not show that an exact integer encoding lost the optimum.','',
        'The rounded route profile has zero quadratic interactions for these grids; its separately '
        'labeled paired unrounded profile remains nonnegative and monotone. Facility and inventory '
        'matrices are not assumed PSD. Coefficient-matrix eigenvalue spacing and symmetric spectral '
        'conditioning describe the chosen canonical representation; neither is an optimization or '
        'quantum gap. Historical total widths are labeled separately from true domain-level counts.','',
        '## Reproduction','',
        'Verify and extract the packet with `pack.py extract`, regenerate tables with `report.py`, '
        'then run `analysis.py` and the pinned `plots.py` environment. These steps do not solve or sample. '
        'Run `replay.jl` to reproduce retained actual proposal decisions; elapsed wall times are not '
        'deterministically reproducible. The packet includes exact environment/source/protocol/input '
        'and raw-record hashes. Private process stdout and licensing configuration are excluded.','']
    (directory/'REPORT.md').write_text('\n'.join(lines))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('report',type=Path)
    render(parser.parse_args().report)
