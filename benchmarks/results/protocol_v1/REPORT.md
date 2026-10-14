# Bounded classical encoding study: protocol v1

The single accepted campaign completed all 680 planned runs, reserving 5,325,120
proposals. It used the four-family corpus and settings frozen in `protocol_v1.toml`.
The result is exploratory: neither new encoding has an established general
advantage. Logical size, coefficient scales and this CPU heuristic do not show
physical-device fidelity, universal search fairness or quantum speedup.

Compiler/sampler source: `2a4f1809ebcc148748f57a8fb2772eca3899e1bb`. Julia 1.10.11;
Float64, one Julia/BLAS thread, an OS one-CPU quota and 4 GiB/no-swap limit.
Campaign wall time was 674.175 s; peak process RSS was
827.96 MiB. The raw Project/Manifest and all dependency
versions are archived. HiGHS.jl 1.26.0 supplied bounded numerical references;
pilots used exhaustive source optima. Numerical solver status/bounds are not
exact-arithmetic certificates.

## Held-out evaluation

Eight held-out instances (two per family), five planned restarts per arm/regime.
Tuning used separate instances and froze cap4 for bounded QUIO and cap1 for the
ToQUBO shim. The tuning ledger, scores and costs remain in the raw archive.
All runs completed as valid records; 22 evaluation and 3 tuning runs were clock
censored and retain partial trajectories. Actual completed proposals were
5,304,189; unspent proposals did not replenish the reserved allowance.

`F` is any visited source-feasible state, including the initial state, not a
penalized-energy or target-domain test. Targets use the independently frozen
reference incumbent and sense-aware tolerance. Time score is first timely hit
or a 2-second failure penalty; work score is first-hit proposal or the common
10,000-proposal cap. These are failure scores, not raw latency or actual work.
Source observations are included in solve timing. Missing hits remain missing.

| Regime | Arm (cap) | F / 40 | Target / 40 | Clock-censored | Mean time score (s) | Mean work score | Unpaired conditional instance gap |
|---|---|---:|---:|---:|---:|---:|---:|
| controlled | native | 26 | 5 | 1 | 1.769763 | 8935.425 | 0.250957 |
| controlled | radix | 25 | 7 | 3 | 1.675212 | 8478.525 | 0.161233 |
| controlled | bounded (4) | 25 | 7 | 3 | 1.673690 | 8478.525 | 0.149244 |
| controlled | toqubo_binary | 20 | 4 | 4 | 1.807332 | 9079.275 | 0.272020 |
| controlled | toqubo_bounded_shim (1) | 29 | 5 | 1 | 1.794279 | 9157.825 | 0.238880 |
| compiler_defaults | native | 26 | 5 | 3 | 1.767316 | 8935.425 | 0.250957 |
| compiler_defaults | radix | 25 | 7 | 0 | 1.675604 | 8478.525 | 0.161233 |
| compiler_defaults | bounded (4) | 25 | 7 | 5 | 1.673037 | 8478.525 | 0.149244 |
| compiler_defaults | toqubo_binary | 23 | 4 | 1 | 1.810231 | 9090.600 | 0.137545 |
| compiler_defaults | toqubo_bounded_shim (1) | 27 | 6 | 1 | 1.743180 | 8935.650 | 0.200935 |

The conditional-gap column is unpaired: arms use different feasible instance sets;
it is not a comparative effect estimate. Native has gaps on 7 instances,
radix/bounded on 7. The paired primary comparisons below use common feasible
restart pairs. All eight per-instance gap differences and their paired counts
are shown in [the generated tables](TABLES.md), including missing entries.

The separate `evaluation.csv` includes snapshot feasibility weighted by archived
multiplicities, missing latency counts and distinct source snapshots. Snapshot
rates have a different observation denominator from F: encodings change sweep
lengths and representation multiplicity. Repeated target representations and
snapshots are not independent source solutions. All valid best points and
archived snapshot feasibility flags were checked against the original sources.

QUIO compiler-default cells intentionally repeat the controlled policy, seeds,
initialization and polynomial. Clock stops can differ. They are calibration
repeats and are not pooled across regimes as independent evidence. ToQUBO defaults
retain actual preprocessing/GCD/linear residuals and constitute a separate
compiler-policy comparison. The pinned upstream binary arm and disclosed exact
bounded shim are distinct arms; upstream `Bounded` was not silently patched.

## Primary paired contrasts

Candidate minus native, aggregated within instance first. Positive F is better;
negative gap/time/work is better. Gap differences use jointly feasible paired
restarts; absent pairs remain missing. Below, n is observed instance differences,
not sample count. The archive retains every one of the eight differences and
paired-restart counts for every endpoint and all secondary contrasts.

| Contrast | Endpoint | Mean difference | Descriptive 95% interval | n | Sign-flip sensitivity p |
|---|---|---:|---|---:|---:|
| radix-native | feasibility | -0.025000 | [-0.175000, 0.125000] | 8 | 1.000000 |
| radix-native | signed_gap | -0.046532 | [-0.084412, 0.017125] | 6 | 0.062500 |
| radix-native | target_time_score | -0.094551 | [-0.353147, 0.093832] | 8 | 0.375000 |
| radix-native | target_work_score | -456.900000 | [-1658.659375, 447.295000] | 8 | 0.375000 |
| bounded-native | feasibility | -0.025000 | [-0.175000, 0.125000] | 8 | 1.000000 |
| bounded-native | signed_gap | -0.060518 | [-0.101081, -0.001326] | 6 | 0.062500 |
| bounded-native | target_time_score | -0.096073 | [-0.361663, 0.093777] | 8 | 0.250000 |
| bounded-native | target_work_score | -456.900000 | [-1658.659375, 447.295000] | 8 | 0.375000 |

The protocol uses 2,000 family-stratified instance/restart bootstrap resamples,
seed99001, paired restart IDs and percentile intervals. Only two instances per
family make these intervals coarse, descriptive and potentially narrow. Sign-flip
sensitivity enumerates all 2^n assignments and assumes exchangeable signs; it is
not a randomized or confirmatory test. There is no multiplicity control. The
bounded conditional-gap interval is negative here, while its sensitivity p is
0.0625 with six observed instances. This is the attainable floor here with five
nonzero same-sign differences and one zero difference. Facility-3011 contributes
a paired-gap estimate from only one jointly feasible restart. The negative interval
does not establish general superiority or erase missing pairs and the lower
observed feasibility rate.

All primary contrasts against native have eight layout-distinct and
exact-target-distinct instances. Radix and bounded differ from each other on
only two of eight targets in each regime, the knapsack pair. The other six are
aliases, so the similar primary outputs are not independent wins. Identity
counts for every contrast/regime and all secondary endpoints are reproduced in
[the generated tables](TABLES.md).

## Structural and timing tradeoffs

Means over the eight selected held-out cells in each regime. Couplers combine
symmetric contributions after shifts/fixed substitution/binary-square folding;
density denominators, coefficient scales and full raw/canonical polynomials are
archived. Variable counts are logical, not physical resources. Matrices use dense
storage; zero coefficients do not allocate sparse storage.

[Generated structural tables](TABLES.md) provide variables, unique couplers,
warm own build time/allocations, canonical minimum-nonzero and maximum
coefficient magnitudes, and their ratio, for all arms and regimes. These values
are recomputed and compared in CI rather than copied arithmetic.

Warm source/native construction is shared once per instance and has separate
fields. Own build includes encoding/backend copies, target extraction and
metadata capture; defensive harness deepcopy is recorded separately and excluded.
Per-run end-to-end fields sum shared native setup, own build and instrumented
solve/observation; do not sum shared setup repeatedly across arms. Queue time is
not applicable to this serial local solver. Snapshot/source checking belongs to
instrumented solve; report generation and raw artifact persistence are outside
those per-run timing fields. Initial fresh-process reporting took 13.552 seconds before the added audits,
including startup/JIT, archive/source QA, bootstrap and result writes; its scope
and limits are recorded in `postprocessing.json`. Per-job archive persistence
was not separately instrumented. Raw provider-style timing is not invented.

The selected small models fit well below the 4 GiB cap. Warm own builds are
milliseconds, and the largest observed allocation cost is the default shim.
This does not demonstrate a storage bottleneck requiring a core rewrite. A
bounded sparse-storage profiling follow-up is optional for larger future models;
this study did not expand sizes or rewrite the compiler after seeing outcomes.

## Frozen hardware subset

`hardware_subset.json` and its generated TOML counterpart retain the
lowest-ordinal held-out source per family. **This rule was selected post hoc,
after the campaign; no pre-evaluation commitment exists.** It is a four-family
demonstration packet, not an unbiased or representative comparative sample.
The selected versus excluded composition is reproduced in [the generated
tables](TABLES.md) and stored in the subset record. All three adverse
feasibility/time-score instances fall outside the selection, while all favorable
time-score instances and the favorable feasibility instance fall inside it.
For radix, selected time-score difference is about -0.277 seconds versus +0.087
for excluded sources; selected feasibility difference is +0.05 versus -0.10.
The same directional composition holds for bounded. Hardware results on this
packet cannot establish a representative advantage. Maintainers and #52 must
review its purpose and composition before any #53 approval; changing the subset
would be a new explicit frozen decision, not a silent replacement.

Four is the radix/bounded encoding parameter, not the native-domain limit or a
verified provider cap. Selected native targets have maximum levels 29/6/7/14
(knapsack/facility/inventory/CVRP), exceeding a hypothetical four-level device.
The subset now records per-arm actual maximum/total levels, cell keys/hashes
and unresolved provider eligibility. No unsupported domain is hidden. #52 must
verify the actual provider contract, and #53 still requires account and
manifest/budget approval. D-Wave/IBM remain conditional binary routes.

| Family | Source | Radix/bounded identical target |
|---|---|---|
| knapsack | knapsack-evaluation-3001 | false |
| facility | facility-evaluation-3011 | true |
| inventory | inventory-evaluation-3021 | true |
| cvrp | cvrp-evaluation-3031 | true |

Identical target payloads must be treated as aliases, not independent encoding
comparisons. Domain levels and weights alone do not bound final device coefficient
magnitudes; normalization/quantization and physical-resource costs remain provider
checks. No hardware job, package release or deployment was performed here.

## Reproduce

Use reporting-code checkpoint
`dd83f3347bf67dab04db9935635774adb721f950` (or its descendant with the same
script hashes), Julia 1.10.11 and archived MOI 1.54.0. Sampling imports still
match frozen campaign source
`2a4f1809ebcc148748f57a8fb2772eca3899e1bb`; source-hash verification covers
`runner.jl`/`run.jl` and all campaign imports. Verify `checksums.json` and unpack
the raw records:

```sh
python3 benchmarks/check_study_artifacts.py extract benchmarks/results/protocol_v1 /tmp/cqt-v1-replay
julia --project=. benchmarks/report.jl /tmp/cqt-v1-replay /tmp/cqt-v1-report
julia --project=. benchmarks/replay.jl /tmp/cqt-v1-replay JOB_SHA256_KEY
```

The verifier uses Python 3.11.4+ stdlib; report/replay uses Julia and the ordinary
package environment. Use the root environment/MOI alignment instructions in `benchmarks/README.md`;
no ToQUBO/HiGHS import is needed for reporting or replay. Apply the same OS memory
scope and outer timeout. The compressed statistics, CSV, tables and subset are derived outputs;
the archive preserves all 680 raw jobs, references, compilation/warm timings,
ordered samples/multiplicities, selection, failures/censoring and runtime hashes.
Do not rerun the campaign to seek a favorable outcome or reproduce clock times.
CI regenerates and compares every derived table/subset and checks that the docs
copy equals this report. Structural coefficient extrema/ratios and all secondary
contrasts are reproduced in `TABLES.md`, rather than left as untracked arithmetic.
The original command was the scoped `benchmarks/run.jl campaign` command in the
benchmark README, with output `/tmp/toquio-cqt-51-campaign-v1`.
