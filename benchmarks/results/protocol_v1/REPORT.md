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

[Generated evaluation tables](TABLES.md) report every arm/regime's feasibility,
target-hit and censoring counts, time/work scores, unpaired conditional gaps and
instances-with-gap counts. Unpaired gap sets differ between arms; the paired
comparisons use common feasible restart pairs. All eight paired gap differences,
counts and missing entries are also generated, rather than copied here.

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

[Generated contrast tables](TABLES.md) report every primary and secondary
endpoint, its distinct-instance counts, descriptive interval and sensitivity
p-value. The standalone page explicitly labels calibration repeats and the
absence of multiplicity control.

The protocol uses 2,000 family-stratified instance/restart bootstrap resamples,
seed99001, paired restart IDs and percentile intervals. Only two instances per
family make these intervals coarse, descriptive and potentially narrow. Sign-flip
sensitivity enumerates all 2^n assignments and assumes exchangeable signs; it is
not a randomized or confirmatory test. Equal tails use a scale-aware summation
roundoff bound, `2n * eps(Float64) * sum(abs, differences)`, recorded for each
endpoint as `tie_absolute_tolerance`. This corrects the compiler-defaults shim
minus binary feasibility sensitivity from 0.5 to 0.625 without changing raw data.
Reported means use a fixed left-to-right reduction so processor-dependent SIMD
summation cannot change the last bits of reproduced artifacts.
There is no multiplicity control. The
bounded-native paired signed-gap interval is negative here, while its sensitivity p is
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

## Post-hoc demonstration subset

`hardware_subset.json` and its generated TOML counterpart retain the
lowest-ordinal held-out source per family. **This rule was selected post hoc,
after the campaign; no pre-evaluation commitment exists.** It is a four-family
demonstration packet, not an unbiased or representative comparative sample.
The selected versus excluded composition is reproduced in [the generated
tables](TABLES.md) and stored in the subset record. Adverse
feasibility/time-score instance counts, whether selected or excluded, are
computed and recorded in the subset and generated tables. Those values expose
the current packet's favorable composition. Hardware results on this
packet cannot establish a representative advantage. Maintainers and #52 must
review its purpose and composition before any #53 approval; changing the subset
would be a new explicit frozen decision, not a silent replacement.

Four is the radix/bounded encoding parameter, not the native-domain limit or a
verified provider cap. Selected native targets exceed a hypothetical four-level
cap; per-arm actual
maximum/total levels are generated in `TABLES.md`.
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
`209fcbaf1671ad49feeb1dae66e0997cc64dda36` (or its descendant with the same
script hashes), Julia 1.10.11 and archived MOI 1.54.0. Sampling imports still
match frozen campaign source
`2a4f1809ebcc148748f57a8fb2772eca3899e1bb`; source-hash verification covers
`runner.jl`/`run.jl` and all campaign imports. The checkpoint's checked script hashes are:

- `report.jl`: `07d7bd17402ec1fd8bed5edca5ee442a96fbd9534f469082992057bbb25e1cf9`
- `study_analysis.jl`: `f993ad9bd4915ebecb53effecc6b45652ef613ef7e211e4084dd22f562da21c4`
- `report_tables.jl`: `bdf3e16ae06b912a5778bc8f23dfdacdb619ad03a8443cfe8f3d778600155b01`

They equal the recorded statistics hashes. A squash/rebase merge must retain a
reachable reproduction revision or update this pin explicitly before publication.
No merge or tag has been performed by this PR. Verify `checksums.json` and unpack
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
CI regenerates and compares the numeric data and generated tables/subset and checks that the docs
copy equals this report. Structural coefficient extrema/ratios and all secondary
contrasts are reproduced in `TABLES.md`, rather than left as untracked arithmetic.
The original command was the scoped `benchmarks/run.jl campaign` command in the
benchmark README, with output `/tmp/toquio-cqt-51-campaign-v1`.
