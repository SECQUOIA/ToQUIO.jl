"""Verify the immutable legacy-example packet and regenerate descriptive tables."""
import argparse
import csv
import gzip
import hashlib
import io
import json
import math
from pathlib import Path
import re
import resource
import statistics
import tarfile
import tempfile
import tomllib

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MAIN = "toquio-example-study"
SUPPLEMENT_NAME = "toquio-example-study-supplement"
ARMS = ['native', 'radix4', 'bounded4-cap2', 'binary-radix2']
OUTPUTS = ("REPORT.md", "comparison.csv", "summary.json")

FILES = {
    MAIN: {"REPORT.md", "REVIEW.md", "protocol.toml", "compare.jl", "summarize.py",
        "results.toml.gz", "summary.json", "comparison.csv", "Project.toml", "Manifest.toml",
        "source-examples.md", "source-hashes.json", "run.log", "checksums.sha256"},
    SUPPLEMENT_NAME: {"protocol.toml", "compare.jl", "results.toml.gz", "run.log", "checksums.sha256"},
}


def unpack(archive, expected_digest, destination):
    """Read only known regular members; never execute or trust archive paths."""
    if archive.stat().st_size > 16 * 1024**2:
        raise ValueError("Oversized compressed packet")
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_digest:
        raise ValueError("Packet SHA256 mismatch")
    expected = {f"{root}/{name}" for root, names in FILES.items() for name in names}
    with tarfile.open(archive, "r:gz") as packet:
        members = packet.getmembers()
        if len(members) != len(expected) or {m.name for m in members} != expected:
            raise ValueError("Unexpected, missing or duplicated packet members")
        if sum(m.size for m in members) > 16 * 1024**2:
            raise ValueError("Oversized packet members")
        for member in members:
            if not member.isfile() or member.size < 0:
                raise ValueError("Only regular packet files are permitted")
            target = destination / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(packet.extractfile(member).read())
    for root, names in FILES.items():
        directory = destination / root
        lines = (directory / "checksums.sha256").read_text().splitlines()
        digests = {}
        for line in lines:
            digest, name = line.split("  ", 1)
            if not re.fullmatch(r"[0-9a-f]{64}", digest) or name in digests:
                raise ValueError("Invalid or duplicate inner checksum")
            digests[name] = digest
        if digests.keys() != names - {"checksums.sha256"}:
            raise ValueError("Incomplete inner checksums")
        for name, digest in digests.items():
            if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
                raise ValueError("Inner checksum mismatch: " + name)
        with gzip.open(directory / "results.toml.gz", "rb") as stream:
            raw = stream.read(100 * 1024**2 + 1)
        if len(raw) > 100 * 1024**2:
            raise ValueError("Oversized decompressed result")
        (directory / "results.toml").write_bytes(raw)
    validate_sources(destination / MAIN, destination / SUPPLEMENT_NAME)


def validate_sources(source, supplement):
    text = (source / "source-examples.md").read_text()
    blocks = re.findall(r"```julia\n(.*?)\n```", text, re.S)
    if len(blocks) != 16:
        raise ValueError("Expected all 16 original source blocks")
    protocols = [tomllib.loads((d / "protocol.toml").read_text()) for d in (source, supplement)]
    for protocol in protocols:
        for key, expected in (("reserved_proposals", 4000), ("max_seconds", 2.0),
                ("restarts", 10), ("seed_start", 9101), ("levels", 4), ("bounded_max_weight", 2)):
            if protocol[key] != expected:
                raise ValueError("Unexpected frozen protocol setting: " + key)
    ordinary = [b for b in blocks if "SomeQUIOSolver" not in b]
    backend = [b for b in blocks if "SomeQUIOSolver" in b]
    if len(ordinary) != 15 or len(backend) != 1:
        raise ValueError("Invalid original example inventory")
    cases = protocols[0]["examples"]
    if len(cases) != 15 or len(protocols[1]["examples"]) != 1:
        raise ValueError("Incomplete frozen example coverage")
    pairs = list(zip(cases, ordinary)) + [(protocols[1]["examples"][0], backend[0])]
    for case, block in pairs:
        if case["source_block_sha256"] != hashlib.sha256(block.encode()).hexdigest():
            raise ValueError("Original source block hash mismatch")
        code = block.split("optimize!(model)")[0]
        if "SomeQUIOSolver" in block:
            code = code.replace("model = Model(() -> ToQUIO.Optimizer(() -> SomeQUIOSolver.Optimizer()))",
                "optimizer = ToQUIO.Optimizer()\nmodel = Model(() -> optimizer)")
        if case["code"] != code:
            raise ValueError("Frozen model differs from original source")
    hashes = json.loads((source / "source-hashes.json").read_text())
    if hashes["commit"] != protocols[0]["source_commit"]:
        raise ValueError("Source provenance commit mismatch")
    if hashes["sha256"]["docs/src/examples.md"] != hashlib.sha256(text.encode()).hexdigest():
        raise ValueError("Original documentation hash mismatch")

def render(source, supplement, output):
    SOURCE, SUPPLEMENT, ROOT = source, supplement, output
    rows = []
    total_runs = total_work = censored = stored_samples = random_checks = 0
    examples = []
    for directory in (SOURCE, SUPPLEMENT):
        raw = directory / 'results.toml'
        with raw.open('rb') as stream:
            result = tomllib.load(stream)
        assert result['source_commit'] == '7a15110a8f90005203c8d2d90b534cb77ebcdfcf'
        assert result['source_path'] == '/workspace/src/ToQUIO.jl'
        assert result['moi_version'] == '1.54.0'
        assert result['protocol_sha256'] == hashlib.sha256((directory/'protocol.toml').read_bytes()).hexdigest()
        assert result['script_sha256'] == hashlib.sha256((directory/'compare.jl').read_bytes()).hexdigest()
        for case in result['examples']:
            assert [a['arm'] for a in case['arms']] == ARMS
            summary = {'title': case['title'], 'reference': case['reference'], 'arms': []}
            reference = case['reference']['objective']
            for arm in case['arms']:
                runs = arm['runs']
                assert len(runs) == 10
                assert [r['seed'] for r in runs] == list(range(9101, 9111))
                assert all(r['reserved_proposals'] == 4000 for r in runs)
                assert all(r['source_observations'] == r['completed_proposals']+1 for r in runs)
                assert all(arm['validation'].get(k) is True for k in
                           ('reference_lift', 'unchanged_penalties', 'polynomial_equivalence'))
                assert arm['validation']['random_states'] == 100
                structure = arm['structure']
                poly = structure['raw_polynomial']
                canonical = structure['canonical']
                n = len(canonical['g'])
                matrix = canonical['G']
                semantic = {'squares': [matrix[i][i] for i in range(n)],
                    'couplers': [matrix[i][j]+matrix[j][i] for i in range(n) for j in range(i+1,n)],
                    'linear': canonical['g'], 'constant': canonical['constant'],
                    'widths': [poly['upper'][i-1]-poly['lower'][i-1] for i in canonical['active']],
                    'sense': poly['sense']}
                def normalize(x):
                    if isinstance(x,dict): return {k:normalize(v) for k,v in x.items()}
                    if isinstance(x,list): return [normalize(v) for v in x]
                    return float(x) if isinstance(x,(int,float)) and x else 0 if isinstance(x,(int,float)) else x
                phash = hashlib.sha256(json.dumps(normalize(semantic), sort_keys=True, separators=(',', ':')).encode()).hexdigest()
                feasible = [r['best_feasible_objective'] for r in runs if r['any_feasible']]
                sign = 1 if case['reference']['sense'] == 'min' else -1
                gaps = [sign*(x-reference)/max(1, abs(reference)) for x in feasible]
                assert all(x >= -1e-7 for x in gaps)
                successes = sum(r['timely_target'] for r in runs)
                work = [r['target_work_score'] for r in runs]
                record = {
                    'example': case['title'], 'arm': arm['arm'], 'reference_objective': reference,
                    'logical_variables': structure['logical_variables'],
                    'max_levels': max(structure['domain_levels']),
                    'couplers': structure['unique_couplers'],
                    'max_coefficient': structure['coefficient_max'],
                    'min_coefficient': structure['coefficient_min_nonzero'],
                    'coefficient_ratio': structure['coefficient_ratio'],
                    'optimum_hits': successes, 'restarts': len(runs),
                    'observed_feasible_runs': sum(r['any_feasible'] for r in runs),
                    'timely_first_feasible_runs': sum(isinstance(r['first_feasible_seconds'], (int,float))
                        and r['first_feasible_seconds'] <= 2 for r in runs),
                    'mean_best_feasible_objective': statistics.mean(feasible) if feasible else None,
                    'mean_best_feasible_relative_gap': statistics.mean(gaps) if gaps else None,
                    'best_observed_objective': (min(feasible) if sign==1 else max(feasible)) if feasible else None,
                    'mean_capped_target_work_score': statistics.mean(work),
                    'warm_optimize_seconds': arm['warm_optimize_seconds'],
                    'warm_optimize_bytes': arm['warm_optimize_bytes'],
                    'completed_proposals': sum(r['completed_proposals'] for r in runs),
                    'clock_censored_runs': sum(r['clock_censored'] for r in runs),
                    'target_polynomial_domain_sha256': phash,
                }
                assert all(math.isfinite(v) for v in record.values() if isinstance(v,float))
                rows.append(record)
                summary['arms'].append(record)
                total_runs += len(runs)
                total_work += record['completed_proposals']
                censored += record['clock_censored_runs']
                random_checks += 100
                stored_samples += sum(len(r['samples']) for r in runs)
            examples.append(summary)
        del result
    
    assert len(examples) == 16 and len(rows) == 64 and total_runs == 640
    assert len({e['title'] for e in examples}) == 16
    summary = {'source_commit':'7a15110a8f90005203c8d2d90b534cb77ebcdfcf',
        'runs': total_runs, 'reserved_proposals': total_runs*4000,
        'completed_proposals': total_work, 'clock_censored_runs':censored,
        'stored_checkpoint_records_audited':stored_samples,
        'random_equivalence_checks':random_checks, 'examples':examples}
    (ROOT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    with (ROOT/'comparison.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]))
        writer.writeheader();writer.writerows(rows)
    
    lines=['# Legacy example encoding comparison', '',
        'All 16 mathematical models in `docs/src/examples.md`, at source commit '
        '`7a15110a8f90005203c8d2d90b534cb77ebcdfcf`, were evaluated locally. '
        'The placeholder-backend example uses the same mathematical model with a '
        'reformulation-only optimizer and the local sampler. No QCI service was used.', '',
        '## Fixed comparison', '',
        'Native, radix with four levels, bounded with four levels and maximum weight two, '
        'and ToQUIO radix with two levels (binary). These parameters were fixed before '
        'the runs; no tuning or selected reruns were used. Each arm also had one '
        'eight-proposal warmup (512 proposals total), excluded from measured results. '
        'The first 15 cases and the '
        'supplemental backend-placeholder model have separate immutable protocols/raw files.', '',
        'Each arm used ten matching seeds, the same native initial state for each seed, '
        '4,000 reserved proposals, a two-second instrumented-solve limit, temperature '
        '2.0 to 0.01, and per-target maximum-coefficient energy normalization. '
        'Independent exhaustive original integer-box enumeration supplied numerical '
        'Float64 objective references. The original model data and selected penalties '
        'are unchanged across arms. Binary means ToQUIO radix2, not a ToQUBO comparison.', '',
        f'Completed **{total_runs} runs**, **{total_work:,} proposals** out of '
        f'{total_runs*4000:,} reserved; **{censored} clock-censored runs**. '
        f'All 64 optimum lifts, {random_checks:,} random target/native polynomial and '
        f'feasibility checks, and {stored_samples:,} saved checkpoint records passed '
        'the implemented audits. Saved records are not every visited state.', '',
        '## Finite-budget heuristic success', '',
        'Each count is the number of ten randomized Metropolis runs finding the source optimum within 4,000 proposals and two seconds. These counts measure search performance, not reformulation correctness. They are descriptive for this '
        'fixed local heuristic, not statistical evidence of general superiority.', '',
        '| Example | Reference | Native | Radix4 | Bounded4 cap2 | Binary |',
        '|---|---:|---:|---:|---:|---:|']
    for ex in examples:
        a=ex['arms']
        lines.append('| '+ex['title']+' | '+f"{ex['reference']['objective']:.8g}"+' | '+
                     ' | '.join(str(x['optimum_hits']) for x in a)+' |')
    lines += ['', '## Structural costs', '',
        'Each entry is logical variables / largest variable-domain level count. '
        'These are logical model sizes, not physical hardware resources.', '',
        '| Example | Native | Radix4 | Bounded4 cap2 | Binary |', '|---|---:|---:|---:|---:|']
    for ex in examples:
        lines.append('| '+ex['title']+' | '+' | '.join(
            f"{a['logical_variables']} / {a['max_levels']}" for a in ex['arms'])+' |')
    lines += ['', '## Coefficients', '',
        'Maximum absolute canonical coefficient after shifting/fixed substitution and '
        'binary square folding. Coefficient ratios, couplers and warm build measurements '
        'are in `comparison.csv`.', '',
        '| Example | Native | Radix4 | Bounded4 cap2 | Binary |','|---|---:|---:|---:|---:|']
    for ex in examples:
        lines.append('| '+ex['title']+' | '+' | '.join(f"{a['max_coefficient']:.8g}" for a in ex['arms'])+' |')
    lines += ['', '## Objective quality', '',
        'Mean best source-feasible objective across runs that observed a feasible point; '
        'the CSV includes denominators and sense-aware relative gaps. This may include '
        'a final observation finishing after the clock limit; timely optimum hits above '
        'exclude late hits.', '',
        '| Example | Native | Radix4 | Bounded4 cap2 | Binary |','|---|---:|---:|---:|---:|']
    for ex in examples:
        lines.append('| '+ex['title']+' | '+' | '.join(
            'missing' if a['mean_best_feasible_objective'] is None else f"{a['mean_best_feasible_objective']:.8g}"
            for a in ex['arms'])+' |')
    lines += ['', '## Identical targets', '',
        'Identical canonical target polynomial and domain hashes, after shifting, '
        'binary-square folding and combining symmetric couplers, are aliases for the sampled '
        'energy model, not independent wins. Source decoding is audited separately.', '']
    for ex in examples:
        groups={}
        for arm in ex['arms']:
            groups.setdefault(arm['target_polynomial_domain_sha256'],[]).append(arm['arm'])
        same=[v for v in groups.values() if len(v)>1]
        if same: lines.append('- '+ex['title']+': '+'; '.join(', '.join(g) for g in same)+'.')
    lines += ['', '## Interpretation and limits', '',
        'The encodings exactly preserve the tested source problem and native penalties '
        'in these checks, while reducing per-variable domains at the cost of extra '
        'variables and changed coefficients. Search benefits vary by example. '
        'Feasibility alone does not establish optimality or generated-slack consistency. '
        'The custom-penalty example deliberately retains a hint below the automatic '
        'sufficient penalty, so no blanket penalized-minimizer equivalence is claimed.', '',
        'Equal proposals are not equal sweeps or source-space moves. Digit '
        'multiplicity, boundary rejections and coefficient-dependent temperature '
        'normalization change the search. Ten restarts, fixed arm order and one warm '
        'compile measurement do not support significance or speedup claims. '
        'Float64 enumeration is a complete source-box search using numerical objective '
        'evaluation, not an exact-arithmetic proof. Random polynomial checks do not '
        'exhaustively certify every encoded assignment. No quantum advantage or QCI '
        'hardware behavior is inferred. This is separate from the frozen protocol-v1 campaign.', '',
        '## Reproduction and provenance', '',
        'Julia 1.10.11, JuMP 1.32.1, MOI 1.54.0; one Julia/BLAS thread, one CPU, '
        '4 GiB memory with no swap; network disabled. Complete numerical references '
        'enumerate no more than 200,000 source assignments per model. No experiment '
        'was rerun while archiving or generating this report.', '',
        'The immutable `benchmarks/legacy_examples/archive.tar.gz` packet contains '
        'both protocols, original execution script, resolved environment, raw '
        'checkpoints and audits. Its original absolute execution paths are a frozen '
        'container interface, not paths required to analyze the archive. '
        'See the benchmark README for sampling reproduction at the pinned source.', '',
        'Regenerate tables with `python3 benchmarks/legacy_examples/report.py`; '
        'verify committed outputs with the same command plus `--check`. '
        'The verifier checks outer and inner SHA256 digests, all 16 source blocks, '
        'execution identity, seeds, work counts and the archived summary. '
        'It never executes archived code or contacts a provider.', '']
    (ROOT/'REPORT.md').write_text('\n'.join(lines))
    assert json.loads((SOURCE/'summary.json').read_text()) == summary
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify committed generated outputs")
    args = parser.parse_args()
    # Analysis of a 70 MiB TOML packet is finite; no sampler or provider is invoked.
    resource.setrlimit(resource.RLIMIT_AS, (2 * 1024**3, 2 * 1024**3))
    digest = (HERE / "archive.sha256").read_text().split()[0]
    with tempfile.TemporaryDirectory(prefix="toquio-legacy-") as tmp:
        temporary = Path(tmp)
        unpack(HERE / "archive.tar.gz", digest, temporary)
        output = temporary / "generated"
        output.mkdir()
        summary = render(temporary / MAIN, temporary / SUPPLEMENT_NAME, output)
        manual = REPO / "docs/src/legacy_examples.md"
        if args.check:
            for name in OUTPUTS:
                if (HERE / name).read_bytes() != (output / name).read_bytes():
                    raise ValueError("Generated output differs: " + name)
            if manual.read_bytes() != (output / "REPORT.md").read_bytes():
                raise ValueError("Manual differs from generated report")
        else:
            for name in OUTPUTS:
                (HERE / name).write_bytes((output / name).read_bytes())
            manual.write_bytes((output / "REPORT.md").read_bytes())
    print(f"Verified {summary['runs']} runs and {summary['completed_proposals']:,} proposals; no sampling.")


if __name__ == "__main__":
    main()
