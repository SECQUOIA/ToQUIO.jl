# Legacy example encoding comparison

All 16 mathematical models in `docs/src/examples.md`, at source commit `7a15110a8f90005203c8d2d90b534cb77ebcdfcf`, were evaluated locally. The placeholder-backend example uses the same mathematical model with a reformulation-only optimizer and the local sampler. No QCI service was used.

## Fixed comparison

Native, radix with four levels, bounded with four levels and maximum weight two, and ToQUIO radix with two levels (binary). These parameters were fixed before the runs; no tuning or selected reruns were used. Each arm also had one eight-proposal warmup (512 proposals total), excluded from measured results. The first 15 cases and the supplemental backend-placeholder model have separate immutable protocols/raw files.

Each arm used ten matching seeds, the same native initial state for each seed, 4,000 reserved proposals, a two-second instrumented-solve limit, temperature 2.0 to 0.01, and per-target maximum-coefficient energy normalization. Independent exhaustive original integer-box enumeration supplied numerical Float64 objective references. The original model data and selected penalties are unchanged across arms. Binary means ToQUIO radix2, not a ToQUBO comparison.

Completed **640 runs**, **2,560,000 proposals** out of 2,560,000 reserved; **0 clock-censored runs**. All 64 optimum lifts, 6,400 random target/native polynomial and feasibility checks, and 231,888 saved checkpoint records passed the implemented audits. Saved records are not every visited state.

## Finite-budget heuristic success

Each count is the number of ten randomized Metropolis runs finding the source optimum within 4,000 proposals and two seconds. These counts measure search performance, not reformulation correctness. They are descriptive for this fixed local heuristic, not statistical evidence of general superiority.

| Example | Reference | Native | Radix4 | Bounded4 cap2 | Binary |
|---|---:|---:|---:|---:|---:|
| Simple Integer Linear Program | 5 | 9 | 10 | 4 | 10 |
| Binary Variables | 3 | 10 | 10 | 10 | 10 |
| Knapsack Problem | 41 | 10 | 10 | 10 | 10 |
| Multi-dimensional Knapsack | 570 | 10 | 10 | 10 | 10 |
| Portfolio Optimization (Simple) | -2.03 | 7 | 8 | 9 | 3 |
| Quadratic Assignment | 46 | 5 | 5 | 5 | 5 |
| Production Planning | 750 | 0 | 0 | 0 | 0 |
| Set Cover Problem | 11 | 10 | 10 | 10 | 10 |
| Specifying Penalty Coefficients | 6 | 8 | 10 | 10 | 10 |
| Reformulation Only (No Solving) | 12 | 10 | 10 | 10 | 10 |
| Examining QUIO Matrices | 2 | 10 | 10 | 10 | 10 |
| Analyzing Penalty Coefficients | 8 | 10 | 9 | 10 | 10 |
| Verification | 8 | 10 | 10 | 10 | 10 |
| Max-Cut Problem | 4 | 10 | 10 | 10 | 10 |
| Facility Location | 395 | 1 | 1 | 1 | 1 |
| With a Backend Solver (local sampler) | 0 | 0 | 0 | 0 | 0 |

## Structural costs

Each entry is logical variables / largest variable-domain level count. These are logical model sizes, not physical hardware resources.

| Example | Native | Radix4 | Bounded4 cap2 | Binary |
|---|---:|---:|---:|---:|
| Simple Integer Linear Program | 3 / 16 | 8 / 4 | 9 / 4 | 12 / 2 |
| Binary Variables | 6 / 4 | 6 / 4 | 6 / 4 | 7 / 2 |
| Knapsack Problem | 7 / 48 | 9 / 4 | 15 / 4 | 12 / 2 |
| Multi-dimensional Knapsack | 7 / 51 | 16 / 4 | 30 / 4 | 22 / 2 |
| Portfolio Optimization (Simple) | 4 / 11 | 12 / 4 | 12 / 4 | 16 / 2 |
| Quadratic Assignment | 16 / 2 | 16 / 2 | 16 / 2 | 16 / 2 |
| Production Planning | 5 / 101 | 20 / 4 | 63 / 4 | 32 / 2 |
| Set Cover Problem | 16 / 3 | 16 / 3 | 16 / 3 | 18 / 2 |
| Specifying Penalty Coefficients | 3 / 16 | 8 / 4 | 9 / 4 | 12 / 2 |
| Reformulation Only (No Solving) | 3 / 6 | 6 / 4 | 6 / 4 | 9 / 2 |
| Examining QUIO Matrices | 3 / 7 | 6 / 4 | 7 / 4 | 9 / 2 |
| Analyzing Penalty Coefficients | 3 / 26 | 9 / 4 | 11 / 4 | 13 / 2 |
| Verification | 2 / 6 | 4 / 4 | 4 / 4 | 6 / 2 |
| Max-Cut Problem | 4 / 2 | 4 / 2 | 4 / 2 | 4 / 2 |
| Facility Location | 27 / 2 | 27 / 2 | 27 / 2 | 27 / 2 |
| With a Backend Solver (local sampler) | 6 / 36 | 19 / 4 | 22 / 4 | 26 / 2 |

## Coefficients

Maximum absolute canonical coefficient after shifting/fixed substitution and binary square folding. Coefficient ratios, couplers and warm build measurements are in `comparison.csv`.

| Example | Native | Radix4 | Bounded4 cap2 | Binary |
|---|---:|---:|---:|---:|
| Simple Integer Linear Program | 310 | 1240 | 620 | 4464 |
| Binary Variables | 36 | 36 | 36 | 48 |
| Knapsack Problem | 219450 | 219450 | 219450 | 219450 |
| Multi-dimensional Knapsack | 1459596 | 1459596 | 1459596 | 1459596 |
| Portfolio Optimization (Simple) | 1950.15 | 6239.36 | 3900.3 | 6239.36 |
| Quadratic Assignment | 1362 | 1362 | 1362 | 1362 |
| Production Planning | 3393300 | 54292800 | 6786600 | 40547425 |
| Set Cover Problem | 80 | 80 | 80 | 80 |
| Specifying Penalty Coefficients | 1980 | 31680 | 7920 | 31680 |
| Reformulation Only (No Solving) | 1812 | 3016 | 3016 | 3016 |
| Examining QUIO Matrices | 577 | 577 | 577 | 822 |
| Analyzing Penalty Coefficients | 5144 | 15616 | 10288 | 15616 |
| Verification | 808 | 1208 | 1208 | 1208 |
| Max-Cut Problem | 3 | 3 | 3 | 3 |
| Facility Location | 5368 | 5368 | 5368 | 5368 |
| With a Backend Solver (local sampler) | 39036 | 957536 | 83264 | 957536 |

## Objective quality

Mean best source-feasible objective across runs that observed a feasible point; the CSV includes denominators and sense-aware relative gaps. This may include a final observation finishing after the clock limit; timely optimum hits above exclude late hits.

| Example | Native | Radix4 | Bounded4 cap2 | Binary |
|---|---:|---:|---:|---:|
| Simple Integer Linear Program | 5.2 | 5 | 5.7 | 5 |
| Binary Variables | 3 | 3 | 3 | 3 |
| Knapsack Problem | 41 | 41 | 41 | 41 |
| Multi-dimensional Knapsack | 570 | 570 | 570 | 570 |
| Portfolio Optimization (Simple) | -2.051 | -2.051 | -2.033 | -2.092 |
| Quadratic Assignment | 48 | 48 | 48 | 48 |
| Production Planning | 639.3 | 696.7 | 636.9 | 706.3 |
| Set Cover Problem | 11 | 11 | 11 | 11 |
| Specifying Penalty Coefficients | 6.4 | 6 | 6 | 6 |
| Reformulation Only (No Solving) | 12 | 12 | 12 | 12 |
| Examining QUIO Matrices | 2 | 2 | 2 | 2 |
| Analyzing Penalty Coefficients | 8 | 8.1 | 8 | 8 |
| Verification | 8 | 8 | 8 | 8 |
| Max-Cut Problem | 4 | 4 | 4 | 4 |
| Facility Location | 477.1 | 477.1 | 477.1 | 477.1 |
| With a Backend Solver (local sampler) | 8.1 | 3.3 | 9.9 | 4.5 |

## Identical targets

Identical canonical target polynomial and domain hashes, after shifting, binary-square folding and combining symmetric couplers, are aliases for the sampled energy model, not independent wins. Source decoding is audited separately.

- Binary Variables: native, radix4, bounded4-cap2.
- Quadratic Assignment: native, radix4, bounded4-cap2, binary-radix2.
- Set Cover Problem: native, radix4, bounded4-cap2.
- Reformulation Only (No Solving): radix4, bounded4-cap2.
- Verification: radix4, bounded4-cap2.
- Max-Cut Problem: native, radix4, bounded4-cap2, binary-radix2.
- Facility Location: native, radix4, bounded4-cap2, binary-radix2.

## Interpretation and limits

The encodings exactly preserve the tested source problem and native penalties in these checks, while reducing per-variable domains at the cost of extra variables and changed coefficients. Search benefits vary by example. Feasibility alone does not establish optimality or generated-slack consistency. The custom-penalty example deliberately retains a hint below the automatic sufficient penalty, so no blanket penalized-minimizer equivalence is claimed.

Equal proposals are not equal sweeps or source-space moves. Digit multiplicity, boundary rejections and coefficient-dependent temperature normalization change the search. Ten restarts, fixed arm order and one warm compile measurement do not support significance or speedup claims. Float64 enumeration is a complete source-box search using numerical objective evaluation, not an exact-arithmetic proof. Random polynomial checks do not exhaustively certify every encoded assignment. No quantum advantage or QCI hardware behavior is inferred. This is separate from the frozen protocol-v1 campaign.

## Reproduction and provenance

Julia 1.10.11, JuMP 1.32.1, MOI 1.54.0; one Julia/BLAS thread, one CPU, 4 GiB memory with no swap; network disabled. Complete numerical references enumerate no more than 200,000 source assignments per model. No experiment was rerun while archiving or generating this report.

The immutable `benchmarks/legacy_examples/archive.tar.gz` packet contains both protocols, original execution script, resolved environment, raw checkpoints and audits. Its original absolute execution paths are a frozen container interface, not paths required to analyze the archive. See the benchmark README for sampling reproduction at the pinned source.

Regenerate tables with `python3 benchmarks/legacy_examples/report.py`; verify committed outputs with the same command plus `--check`. The verifier checks outer and inner SHA256 digests, all 16 source blocks, execution identity, seeds, work counts and the archived summary. It never executes archived code or contacts a provider.
