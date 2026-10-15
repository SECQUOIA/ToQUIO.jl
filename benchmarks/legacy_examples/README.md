# Legacy examples: immutable offline comparison

The [generated report](REPORT.md) covers all 16 mathematical models in the old
manual, using four encodings and ten starts each. It is a local heuristic
comparison, separate from the frozen four-family protocol-v1 campaign and QCI.
Its optimum-hit counts do not test reformulation exactness.

## Verify or regenerate

Use Python 3.11+ (standard library only), a 4 GiB/no-swap OS scope and a
180-second timeout:

```sh
python3 benchmarks/legacy_examples/report.py --check
python3 -m unittest discover -s benchmarks/legacy_examples -p 'test_*.py'
```

Omit `--check` to regenerate the report, CSV, compact JSON and matching manual
page. This performs no sampling, provider calls or archived-code execution. The
analyzer also applies a 2 GiB address-space cap. It verifies outer/inner digests,
source blocks and the sole placeholder-backend adaptation, protocol/script
identity, all seeds/work counts and equality with the archived compact summary.

The complete 3 MiB `archive.tar.gz` packet is immutable: 640 measured runs,
2,560,000 completed proposals, zero censoring, 64 eight-proposal warmups, resolved
environment, original script/protocols, source hashes and ordered checkpoints.
The sixteenth model ran separately because its original backend was a placeholder;
only that wrapper changed. Failed or unfavorable outcomes were not replaced.

## Repeat sampling at the original source

Sampling is unnecessary for artifact verification and will not reproduce elapsed
times exactly. To repeat the experiment deliberately, use a fresh checkout of
`7a15110a8f90005203c8d2d90b534cb77ebcdfcf` and Julia 1.10.11. Extract the packet
with a data-only tar extractor, verify each directory's `checksums.sha256`, and
keep original results untouched. Its `compare.jl` is a frozen container entry
point: mount the checkout at `/workspace` and either extracted protocol directory
at `/study`, copy the archived Project/Manifest into `docs/examples`, and run:

```sh
julia --startup-file=no --project=/workspace/docs/examples /study/compare.jl
```

Use a separate writable copy of each protocol directory, one CPU, 4 GiB/no swap,
one Julia/BLAS thread, and a 20-minute outer timeout (10 for the supplemental
model). Instantiate the pinned environment first; disable container networking
and pass no credentials during execution. The frozen script contains literal
protocol settings, so editing only its TOML is not a supported tuning interface.

## Exactness regression

`test/unit/exact_ilp.jl` separately enumerates every target assignment of the
manual's simple ILP. It uses exact integer energy evaluation with an explicit
overflow bound and an independent penalty equation. All four target minima are 5
and decode to `(5,0)`, regardless of a heuristic's finite-budget success rate.
This is a complete check of that example, not a claim that every larger model
has been exhaustively enumerated.
