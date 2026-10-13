# CQT encoding study: protocol v1

This is the versioned design for [issue #46](https://github.com/SECQUOIA/ToQUIO.jl/issues/46).
It is frozen for human review; integration of this PR accepts v1. The numerical
settings live in `benchmarks/protocol_v1.toml`. A run must archive that file's
hash, this document's hash, executable source revisions and its resolved benchmark
Manifest before evaluation. This protocol is not a report of an executed campaign.

## Questions and supported models

The supplied CQT Year 4 proposal motivates two **hypotheses**: bounded-domain
radix maps may improve quality/time when native integer domains exceed available
levels; bounded-weight maps may improve conditioning under limited coefficient
precision. Neither predicts a universal advantage. Negative or mixed results
satisfy the research milestone when the complete frozen comparison is reported.

The contract covers finite integer/binary domains, integer-valued affine equality
and inequality rows, and affine/quadratic objectives. The four-family campaign
uses linear objectives, permitting a capable direct MIP reference. Tiny quadratic
fixtures validate algebra, not an unplanned nonconvex solver campaign. Continuous
discretization, nonlinear constraints and the proposal's other research strands
are excluded. Four levels is a computational study setting, not a verified limit
of QCI or another device. Live access, device limits and spending remain #53 gates.

## Provenance recovery and comparison pins

A bounded recovery session on 2026-10-13 inspected the proposal-era ToQUIO tree
`f6e619a508a579b83af802715108fed5c36f408d`, fetched history for benchmark/data/result
paths, public branch inventory, the `px/encoding` prototype and the supplied
workshop link. The session was limited to 20 minutes and ended after these reads.
No archived campaign generators/raw results/version ledger were recovered from
those inspected sources. This is not a claim that they cannot exist elsewhere.

| Material | Verified provenance and reuse |
|---|---|
| Current ToQUIO foundation | `56a2abd075575038efd53ac1ce97ea0d12c3fc5a`; MPL-2.0; metadata, penalty controls and source feasibility |
| Older encoding prototype | `21279a12a7e7f1b7e4164b2cf54a4cad4b045b57`; MPL-2.0; design context, not a validated encoder or benchmark corpus |
| ToQUBO comparator | `69ac52592f4c47ed2168bf480c9947d1fcbbfc2c`; Project reports 0.7.1; MPL-2.0; exact source pin, not a registry-install claim |
| Workshop paper | [OpenReview reference](https://openreview.net/forum?id=4XxXUzpRAa); full PDF/browser and public API access remained gated/403; an indexed implementation excerpt was available, not complete campaign evidence |
| Classical reference | [HiGHS.jl v1.26.0](https://github.com/jump-dev/HiGHS.jl/releases/tag/v1.26.0); supports Julia 1.10; actual HiGHS_jll/library version recorded by the runner |

The proposal's historical structural/device-performance statements remain
unverified here. New, repository-authored instances use MPL-2.0 and explicit
parameters; no historical reproduction is claimed. #50 owns a separate benchmark
Project/Manifest with ToQUBO at the above commit and HiGHS.jl exactly 1.26.0.
HiGHS requires MOI >=1.34; benchmark resolution must respect that without changing
the package's MOI1.11 compatibility floor. The executing ToQUIO revision must
include #47–#49 and be recorded exactly; the foundation pin alone lacks encoders.

### Bounded binary comparator correction

The pinned [ToQUBO bounded interval source](https://github.com/JuliaQUBO/ToQUBO.jl/blob/69ac52592f4c47ed2168bf480c9947d1fcbbfc2c/src/encoding/variables/interval/bounded.jl)
uses a residual interval of width `d+r` plus `r-1` digits of weight `mu`, where
`W=r*mu+d`. An independent source-formula enumeration finds width3/cap2 maps to
`0:2`, and width6/cap2 maps to `0:7`. Width20/cap2 produces weights
`[1,2,4,3,2,2,2,2,2,2,2,2,2]`, image `0:28` and a weight4 exceeding cap2.
For `0<W<mu`, the formula also calls its allocator with `r-1=-1`. This is a
latent negative-count request whose runtime effect on the pinned target is
unverified, not another demonstrated coverage failure: width1/cap2's arithmetic
image is exactly `0:1`. Pure-arithmetic fixtures preserve that distinction and
the demonstrated width3/6/20 failures without a dependency.
This audit is not full compiler execution.
It fails the exact box-image contract needed here. The native `Bounded` method
therefore cannot be an unchecked baseline at this pin.

Freeze the arm name **toqubo_bounded_shim**. #50 owns a small experiment-only
ToQUBO interval-method adapter emitting exactly
`protocol_layout(W; levels=2, max_weight=mu)` and offset L. It uses the pinned
compiler's binary variable allocator, not `Binary` on an upstream residual,
and returns an affine map
without digit-enforcement penalties. Apply it to original integers and slacks.
Record adapter revision/hash and distinguish it from upstream `Bounded` in every
result. No vendor source patch, silent alternate pin, or native-method performance
claim is allowed. If its actual compile/decode preflight fails, stop the campaign
and report the failed arm; do not drop it and call the comparison complete.
The shim is ToQUIO-authored and shares a construction with the QUIO bounded arm;
it is not an independent encoder. The emitted-map coverage and polynomial gates
below protect against common-mode mistakes instead of trusting layout agreement.

## Five arms and two regimes

| Arm | Domain map | Level/weight settings |
|---|---|---|
| native | Identity native QUIO | Original integer intervals, including slacks |
| radix | Exact bounded-tail radix layout | At most 4 values per digit |
| bounded | Same coverage construction with a weight cap | At most 4 values; pilot cap2, later selected from 1/2/4 |
| toqubo_binary | Pinned ToQUBO Binary | Binary original/slack digits; no lossy real encoding |
| toqubo_bounded_shim | Disclosed exact binary bounded adapter | Binary digits; pilot cap2, later selected from 1/2/4 |

**Controlled:** compile the source once with ToQUIO offset1/scale1 and no hints.
Encode that complete native QUIO model, including its slacks, for every arm.
The two ToQUBO arms compile the native QUIO model (only bounds/integer constraints)
with the specified variable method. This preserves the same source penalty
magnitudes/residuals; any additional enforcement penalty invalidates this arm.
Set and record ToQUBO `Discretize=false` for this bounds/integer-only input,
and record the actual objective sense; no residual or polynomial rescaling is
permitted. The pin parses integer originals without real-ATol encoding.
Compare the sense-normalized polynomial after decoding, including the constant.
Native intervals may exceed four levels: this is a CPU control whose hypothetical
device ineligibility must be reported, not hidden by changing its domain.

**Compiler defaults:** each compiler receives the original constrained source.
QUIO arms use ToQUIO defaults followed by their domain map. Binary arms use pinned
ToQUBO's defaults except the named encoding method: QuadraticPenalty,
ObjectiveRangePenalty with its recorded fallback behavior, offset1/scale1,
MaxPenaltyUpdates=0 and the same method for slack encoding. Preserve and archive
actual applied coefficients, slack widths, preprocessing and target sense.
Retain and record `Discretize=true`: pinned affine-inequality compilation then
calls `variable_ℤ!` for slacks rather than real-ATol encoding. Its GCD residual
scaling and removed rows must be archived and included in reconstruction; these
are compiler-default differences. This source inspection is not proof that a
future compiled instance passes the mandatory emitted-map gates.
Automatic policies can differ. This is an end-to-end comparison, not a matched
penalty causal estimate. No weak-penalty sweep or precision perturbation enters
the primary campaign; the worked failure below is a diagnostic control.
ToQUIO's three compiler-default arms have the same polynomial and encoding as
their controlled cells. Use the same native-full-box initialization and canonical
lift, RNG streams and schedule for these arms in both regimes. These are
intentional calibration repeats, with identical trajectories at equal completed
work (clock stops may differ), not independent additional data or evidence of a
compiler-default regime effect. Do not pool regimes. The distinct ToQUBO default
cells supply the compiler-policy comparison against these repeated controls.

## Exact affine contract

Let the native full state be `z=[x;s]`, with integer endpoints
`L=ceil(l)`, `U=floor(u)`, and `W=U-L`. Reject an empty interval. Each variable
must have a map `z_i=L_i+sum(w_ij*d_ij)`, `0<=d_ij<=m_ij`, with integer digits.
For every permitted digit state, its image lies in the native domain; every
native value has a preimage. Negative offsets are retained. Fixed variables
have a constant expansion and no digit; their source values must be restored.

The proposed reference construction starts with coverage `C=0`. While `C<W`,
choose `w=min(C+1,W-C)` (also `min(w,mu)` for bounded),
`m=min(levels-1,floor((W-C)/w))`, and increase `C` by `w*m`. Each digit has
`m+1<=levels` values. The inequality `w<=C_old+1` prevents gaps between shifted
covered intervals; the endpoint sum equals W exactly. A final residual digit can
be redundant. Radix uses full powers where they fit, with a bounded tail; it is
not a promise of the information-theoretic minimum digit count. At levels2 the
unbounded construction reduces to ToQUBO's bounded-tail binary map. Bounding
weights alone does not bound final coupler magnitudes: penalties/source terms
also contribute. Measure those coefficients rather than claiming a device cap.

Nonunique representations are allowed, and all are decoded identically. They
change state multiplicity and local-search neighborhoods; polynomial equivalence
does not imply equal sampling distributions. A deterministic right inverse
(canonical lift) is required for shared controlled initialization and replay;
`lift_native_state` is authoritative for ToQUIO arms. Experiment adapters and
the executable protocol helper use the same decreasing-weight order, with ties
in original digit order. Archive the actual ordered maps and initial digit state;
its roundtrip must be tested on every tiny native state. Source feasibility
reuses #34 after full composed decoding; no rounding, repair or target-energy
inference is permitted. Source objective values come from original functions.

For `z=a+B*d` and `P(z)=z'G*z+g'z+gamma`, substitute

```math
G_d=B^TGB,\quad g_d=B^T(g+(G+G^T)a),\quad
\gamma_d=a^TGa+g^Ta+\gamma.
```

This handles nonsymmetric matrix storage. For a canonical MOI quadratic function,
a diagonal ScalarQuadraticTerm coefficient c contributes `c*z_i^2/2`; an
off-diagonal term contributes `c*z_i*z_j`. Thus emit diagonal coefficient `2G_ii`
and one off-diagonal coefficient `G_ij+G_ji`, never blindly double every entry.
Global source-penalty guarantees carry through the exact map; weak hints remain
heuristic. Mathematical substitution does not improve an insufficient penalty.

Compute endpoint/weight/count arithmetic in checked integers or BigInt before
allocation. Convert coefficients only with representability checks, and reject
nonfinite transformed matrices, linear terms, constants or decoded values.
The Float64 campaign uses small exact integer inputs; preflight rejects loss of
integer endpoints/weights or failed polynomial parity. A provider roundtrip must
also check actual maximum levels and precision. Quantization/normalization/device
errors are #52 diagnostics and #53 confounders, not source-map exactness claims.

## Frozen corpus

Four fixed pilots validate all families. Generated tuning/evaluation sizes and
seeds are in the TOML; each family has one tuning and two evaluation instances.
Use Julia MersenneTwister with the stated instance seed, integer inclusive draws
and fixed index traversal. Archive concrete parameters, source models and hashes
so replay uses saved data rather than an assumed future RNG version. Pilot IDs
identify constant fixtures and are not claimed effective random-generator seeds.
Freeze those parameters and hashes in the manifest before any arm compiles or
reference solve starts. #50 must record the explicit draw order and construction
code hash; compilation cannot change a generator draw or replace an instance.

The family-major ordinal order is fixed (each row is pilot, tuning, evaluation1,
evaluation2); use these ordinals for every stage, including seeded pilot warmups:

| Family | Pilot | Tuning | Evaluation 1 | Evaluation 2 |
|---|---:|---:|---:|---:|
| Knapsack | 1 | 2 | 3 | 4 |
| Facility | 5 | 6 | 7 | 8 |
| Inventory | 9 | 10 | 11 | 12 |
| CVRP | 13 | 14 | 15 | 16 |

| Family | Fixed pilot | Tuning/evaluation generator |
|---|---|---|
| Knapsack | 2 variables: weights[2,1], profits[3,2], upper[2,1], capacity3 | 6 items, quantities0:3; weights1:5, profits1:9; capacity=floor(0.45*sum(weights*upper)); maximize profit |
| Capacitated facility location | 2 facilities/2 clients; demands[1,1], capacities[2,2], fixed[4,3], shipping[2 1;1 2] | 3 facilities/4 clients; demands1:3, fixed costs1:9, shipping1:5; round-robin witness assignments; capacity_j=witness load_j+1; minimize fixed+shipping |
| Inventory/lot sizing | 2 periods; demands[1,1], initial/final stock0, quantity/stock upper2; setup2, unit production1, holding1 | 4 periods; demands1:3, quantity upper3, stock upper6, setup costs1:5, production1:3, holding1; minimize cost |
| CVRP | 2 customers/1 vehicle/capacity2; demands[1,1], points(0,0),(1,0),(0,1) | 4 customers/2 vehicles/capacity8; demands1:3, customer coordinates0:5; depot(0,0), Manhattan distances; minimize travel |

Facility variables are binary opens/assignments, each client assigned once,
assignment<=open, and weighted assignments<=capacity*open. Inventory variables
are bounded integer production/stock plus binary setups; balances hold each
period, production<=upper*setup and terminal stock is zero. CVRP uses directed
binary arcs (no self arcs), customer in/out degree1, depot degrees equal vehicle
count, and integer cumulative loads in `[d_i,Q]` with MTZ capacity rows
`u_i-u_j+Q*x_ij<=Q-d_j`. The two routes can split four demands into pairs, each
load<=6<8, supplying a known feasible witness. Coordinates/costs do not affect
that guarantee. Store each independent witness and verify it before compilation.

Pilot sources have respectively 6,64,324,256 box assignments before constraints.
Parity preflight enumerates source/compiled boxes only after reserving their
exact BigInt counts. Limit each enumeration to one million assignments and total
preflight to four million, stream states, and never allocate a Cartesian state
array for an unchecked domain. Verify full image coverage, all-state polynomial
parity and source-optimum agreement. Any refused/exhausted check is incomplete
validation and stops the full campaign; no larger substituted pilot is permitted.

### Generated-instance exactness gates

Tiny level4 pilots use identity maps for the QUIO arms and cannot alone validate
multi-digit encoding. Before sampling, #50 must apply the following checks to all
12 generated models, both regimes, all arms and every tuning candidate:

- Read **emitted** original/slack expansions and target bounds from ToQUIO
  metadata or ToQUBO `VariableEncodingFunction`/`SlackVariableEncodingFunction`.
  Require exact integer offsets, weights and digit bounds with no lossy real-ATol
  path, and compare with the declared layout (identity for native, levels4 radix
  or bounded, levels2 Binary or shim). Account explicitly for any removed fixed
  variables/slacks and compiler-default residual scaling.
- Independently compute reachable sums by dynamic programming on those emitted
  digits, not by calling the construction again. Require image exactly
  `L+{0,...,W}`, with no holes or out-of-domain sums. Limit W to64 before allocation;
  test the canonical-lift roundtrip for every value of every original and slack
  interval. This avoids an exponentially large full-state enumeration.
- Check constant- and sense-inclusive polynomial parity on 64 seeded random digit
  states per compiled cell, plus canonical lifts of the source witness and frozen
  reference incumbent with the corresponding exact residual slacks. For preflight
  RNG use MersenneTwister seed `98001+10000*ordinal+100*arm_index+10*regime_index+cap`,
  taking cap0 for unbounded arms and the listed arm/regime order. These checks are
  not sampler restarts. Controlled arms compare with the single native polynomial;
  default arms compare with their own independently reconstructed pre-encoding
  polynomial, using archived original objective, applied penalties, residual
  scales, slack domains, removed rows and sense. Defaults must not be compared as
  if source penalties matched. Use the TOML absolute/relative energy tolerances.

Any missing map, noninteger coefficient, incomplete roundtrip or parity failure
stops the full campaign. These gates are required runner work in #50, not a claim
that this protocol PR has already executed future encoders. Unit tests extend
independent coverage/lifts through width64. Archive gate inputs/results and RNG
seeds. Record each instance/arm's normalized offset/weight/digit-bound layout
equality with native and radix (order-independent within each native variable);
report the number of structurally distinct instances for every contrast. Widths
up to3 yield native identity, and cap4 equals radix through width19: zero contrasts
on those cells are structural degeneracy, not evidence of an empirical null effect.

## Independent references and targets

Exhaustively enumerate original pilot boxes to certify their source optima.
Before tuning, solve each of the twelve generated source models once with
HiGHS.jl 1.26.0: one thread, seed777, 10 seconds, relative/absolute MIP gap0.
Record termination, feasible original incumbent, objective bound with its correct
sense, solve time and tolerances. Validate returned values with #34; never round
or use a competing encoded arm to choose the reference. Freeze/hash references
before any tuning/evaluation. A solver-optimal status is a numerical certificate
within its tolerances, not an exact-arithmetic proof. Larger targets are labeled
best-known feasible values under this budget even when optimality is reported.
Missing/invalid references stop the campaign; do not replace the instances.

With `sigma=+1` for minimization and `-1` for maximization, report signed source
gap `sigma*(f-f_ref)/max(1,abs(f_ref))`. Positive is worse, negative can improve
a best-known reference and must remain visible. The denominator uses one native
objective unit near zero. Tiny targets require the exact optimum within absolute
1e-9; generated targets allow gap<=0.01 plus absolute1e-9. The target is fixed
independently of all encodings and does not certify a heuristic's optimality.

## Controlled Metropolis and budgets

#50 implements the experiment-only single-site integer Metropolis kernel.
Each proposal chooses an active digit uniformly and an independent +/-1 with
equal probability; out-of-domain proposals reject and still count. Initialize
uniformly in the native full box, then canonical-lift the identical native state
for controlled arms and the repeated ToQUIO default cells. ToQUBO compiler-default
arms share original-variable initialization; compiler-specific auxiliaries use
recorded seeded initialization and are a confounder. No source optimum or
reference witness seeds the competing samplers.
Use separate MersenneTwister streams: initialization seed=effective run seed,
proposal seed=effective run seed+1000000000; these seed values are identical
across paired arms. Record both identities. Effective run seed=listed replicate seed+10000*instance
ordinal from the family-major table. Warmups use replicate seed39001.

Normalize minimization energy as `sigma_target*P_target/S`, with
`S=max(1,source objective box range)` shared across arms. Read actual compiled
sense: a compiler may already negate a maximization objective. Use the geometric
schedule from T=2 to 0.01 across the reserved proposal count (T=2 for one proposal),
and Metropolis acceptance `min(1,exp(-delta_energy/T))`. Consume a declared fixed
RNG draw sequence per proposal, including rejects, and validate incremental energy
changes against full evaluation, boundary rejections and exact tiny-state behavior.
Retain +/-1 even for binary digits, as the declared reference kernel requires;
one direction is then always invalid. Record per-run boundary rejections,
in-domain proposals, accepted moves and energy rejections. Require boundary
rejections+accepted moves+energy rejections=completed work, and
in-domain proposals=accepted moves+energy rejections. The binary arms' boundary
waste is an explicit confounder.
Replay an interrupted run using the original reserved proposal count for its
temperature schedule, stopping at the archived completed-work count; seeds alone
cannot reproduce a wall-clock stop, and shortening the schedule changes the path.
This is a local-search control, not a physical QCI simulator.

A sweep is N_active proposals. Schedule `min(proposal_cap,sweep_cap*N_active)`;
the equal caps below make the proposal count equal across nonempty arms. Stop
also at the 2-second per-run limit, checked every proposal, or a global ledger
limit. Fixed targets are evaluated once without a proposal. Warm each
family/arm/regime once on pilot data before measured timings; warmups consume
the same ledger but never contribute measured outcomes.

| Stage | Instances/methods/regimes/repeats | Starts | Proposal cap/start |
|---|---|---:|---:|
| Warmup | 4*5*2*1 | 40 | 128 |
| Pilot smoke | 4*5*2*3 | 120 | 1000 |
| Bounded tuning | 4*2 bounded arms*3 weight caps*5, controlled only | 120 | 10000 |
| Evaluation | 8*5*2*5 | 400 | 10000 |

Reserve at most 680 starts and 5,325,120 proposals, including warmups; at most
one hour wall time, one CPU/BLAS thread, 4GiB resident memory, no swap, 256 compiled
variables and 512MiB artifacts. Apply OS limits to compiler/reference/sampler
processes too. Check dimensions before dense matrices; reserve counts before any
sampler/enumerator call. Keep failed attempts and their consumed/reserved budgets;
no extra restarts, enlarged search or silent data replacement. An interruption
retains incomplete evidence. Campaign completion requires all planned cells.
The worst frozen CVRP unary binary layout needs 216 variables: 20 arcs,
4 loads of width7 and 12 slacks of width14. Every arm/cap/regime is bounded by
that dimension; tests derive conservative family widths from the generator
ranges. A 256-square Float64 matrix uses 512KiB, so the dimension allowance is
compatible with the memory cap; OS enforcement still covers compiler overhead.

Select one global weight cap independently for each bounded arm on tuning data:
highest mean per-instance target-success fraction, then lowest mean capped target
time, then smallest cap. Freeze both choices before evaluation and use them in
both regimes. Radix levels and all temperatures/penalties stay fixed. Record all
120 tuning starts and their CPU/build costs as overhead, not evaluation evidence.

## Endpoints, failures and statistics

For every visited state, decode and check the original model to observe first
target attainment and the best feasible objective; include this observation cost
in measured solve latency. A visited state is the initialization plus the current
chain state after each proposal's accept/reject decision. Rejected candidates
are not observed states; repeated chain states retain their multiplicity.
Use monotonic `time_ns`: start immediately before
initialization and canonical lift, after compilation/warmup, and stop after the
final observation. First-hit latency includes initialization/lift and decoding;
timely hits require the observation to finish within2s. This is an instrumented
sampler latency, not bare kernel/device latency. Retain initial-state target hits
separately with proposal index0. Record
sample observations after each complete sweep and the final partial sweep;
rejected/duplicate states retain multiplicity and ordering. Read counts are not
independent experimental replicates. No-feasible-state runs have missing gap,
not zero. Record first feasible/target time, proposal index, actual elapsed time,
completed work, termination and censoring flags; unavailable timings stay missing.

Primary feasibility is `F_imr=1` iff planned run r visits at least one original-
model-feasible state (including initialization), else0. Estimate it per instance/
arm as `sum(F_imr)/5` over **all five planned evaluation restarts**. Final-state
feasibility and the correlated per-sweep feasible-read fraction are secondary
diagnostics, with explicit sample counts; they cannot replace this endpoint.
Primary quality also includes signed best-feasible gap with its missingness count.
Primary time output is first-target latency with
failures plus a **capped target-time score**: observed first hit, or the common
2-second failure penalty if no hit. The score is not actual spent time when a
proposal cap ended early and is not a 99%-reliability claim. Report raw censored
observations and target-success fractions alongside it; zero successes remain
zero with all raw target times missing and score2, never fabricated finite hits.
Hits observed after the run deadline do not count as timely successes and are
retained as overshoot diagnostics. Missing timings invalidate the corresponding
time comparison, not the quality data when source observations remain validated.
Also report proposals to first target (initial hit0), raw no-hit proposal censoring
and a capped work score: first-hit index or the common stage proposal cap for no
timely hit. The work score is not actual spent work; record the smaller actual
work at clock censoring. It supplies a common work penalty alongside uneven
wall censoring and exposes observation overhead; the 2s time score can largely
track the success indicator and must not be called a pure speed metric.

A run interrupted by its ordinary 2s cap is a valid partial trajectory: its
validated feasible visits/gap remain, and an absent timely target receives score2.
A crash, corrupted/missing trajectory or unverifiable decoding is an **invalid
planned run**: assign F=0, target failure, time score2, work score equal to its
stage cap and gap missing, even if a partial file suggests a hit. Count and
describe these separately; no rerun or selective deletion is allowed. Missing
clock data invalidate raw latency comparisons, not validated quality; show the
missing count and mark any affected time-score contrast incomplete rather than
silently dropping its replicate. A preflight-refused cell, global quota exhaustion
or externally interrupted campaign is an incomplete campaign with no completed-
campaign aggregate; preserve partial records and the reason, never relabel it a
sampler failure or report a completed result. All planned cells must be accounted
for before a complete exploratory report is allowed.
The same F, invalid-run, ordinary clock-censoring, target-time and work-score rules
apply to all120 tuning starts, with five planned replicates per instance/arm/cap
cell. Select caps using the all-five denominator, including invalid failures;
a preflight/global failure instead leaves tuning incomplete and stops evaluation.

Structural outputs include allocated original/native/encoded integer and binary
counts, each domain's levels, active variables, build time, allocated bytes and
observed peak resident memory. For coefficient/coupler comparisons, use a common
canonical polynomial: shift active coordinates by their lower endpoints,
substitute fixed coordinates into the constant/linear terms, and fold each
binary-coordinate square into its linear term. Report nonbinary square,
linear and unique off-diagonal coefficients `G_ij+G_ji` separately; the constant
is archived but excluded from coefficient ratios. This avoids comparing storage
conventions or duplicate terms as physical couplers. Density is
`2*couplers/(N_active*(N_active-1))` (0 for N_active<2). Report max/min-nonzero
absolute coefficients and their ratio (missing if no nonzero coefficients).
Archive both raw compiled and canonical matrices/offsets so this normalization
can be replayed. Time warm source construction, reformulation, encoding/backend
copying, and solve/observation separately; report their sum for end-to-end cost.

Predeclare primary controlled contrasts radix-native and bounded-native.
Binary-vs-native, bounded-binary-vs-binary and compiler-default contrasts are
secondary. Aggregate repeat outcomes within each instance first; instances are
the cross-instance unit. Report paired instance differences, stratified by family,
and 95% percentile cluster bootstrap intervals with 2000 resamples/seed99001.
Resample instances within each family, retaining paired method records and
resampling paired restart IDs within selected instances. Pair methods by the
same instance and listed replicate seed. For gaps, compute run-level differences
only where both F=1 and both gaps are validated, then the per-instance mean over
those pairs, reporting its count (0 means missing). Report all eight paired
instance differences, including missing entries. Feasibility/time/work-score
differences use each arm's mean over all five planned runs, including the failure
rules above. Bootstrap gap statistics retain this pairing and missingness rule.
Label the percentile intervals **descriptive**: two instances per family produce
coarse resampling and potentially narrow intervals, not reliable confirmatory
uncertainty. Also report the two-sided paired sign-flip sensitivity p-value for
each contrast/endpoint by enumerating all2^n sign assignments of its n observed
instance differences and counting `abs(mean(flipped))>=abs(mean(observed))`;
n=8 gives256 assignments, gaps may have n<8 (n=0 means missing). This diagnostic
assumes exchangeable signs, is not a randomized experiment test, and is not
confirmatory. There is no multiplicity control across two contrasts and at least
three primary endpoints. Describe gap comparisons as conditional and do not
hide failure rates. Eight evaluation instances/five repeats support a bounded
exploratory result, not a broad superiority or quantum-speedup claim.

Archive effective seeds, run order (shuffle seed99011), schedule/work/timing boundaries,
source parameters/models, exact matrices/decoders/penalties, snapshots, all raw
sample multiplicities, references, statuses, errors, locks and dependency/source
hashes. Record solver/precision/neighborhood/multiplicity differences as confounders.
Any protocol change requires a new version/manifest before evaluation; preserve
old evidence instead of tuning mandatory scope after seeing results.

## Tiny worked example and implementation gates

The knapsack pilot maximizes `3x+2y` with `2x+y<=3`, integer `x in0:2`, `y in0:1`.
Its exact source optimum is 5 at (1,1). Slack is0:3 and default magnitude is9.
The explicit binary map `x=d1+d2,y=d3,s=d4+2d5` maps32 digit states onto24 native
states with duplicate representations, preserving every polynomial value.
An illustrative magnitude0.25 instead gives target optimum 7 at source-infeasible
(2,1). That is an override-risk example, not an automatic compiler defect.

```@example protocol_v1
include(joinpath("benchmarks", "protocol_example.jl"))
```

This script is an executable algebra specification, not a production encoder or
campaign runner. #47 integrates composed decoding and source feasibility;
#48/#49 implement/validate the two layouts; #50 owns the four-family corpus,
ToQUBO shim, sampler, manifest/gates and runner; #51 executes the bounded report;
#52 validates offline provider roundtrips; #54 closes software documentation/replay.
Human review/integration accepts the protocol; the later live campaign still
requires its concrete approved manifest, account access and budget in #53.
