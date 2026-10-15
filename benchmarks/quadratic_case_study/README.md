# Fresh quadratic case study

This isolated study independently generates new instances of four quadratic
integer model families and compares exact integer encodings. It does not reuse
historical instance files, seeds, implementation code, or measured outcomes.
The package runtime has no new dependencies; licensed and comparison solvers
belong only to this optional study environment.

The protocol and all 456 concrete profiles are frozen for issue #71. All 2,736
structural cells passed allocation admission. Validation passed 631 Julia checks,
independent artifact regressions, and a manufactured four-family integration run
covering 28 cells and 180 replay-audited chains. No full-campaign result is claimed
by this preparation. Historical archived studies remain separate.

## Models and fresh draws

All variables are bounded integers. Source objectives use the convention
`x'Q*x + g'x`: both symmetric off-diagonal entries contribute. All cost/quantity
units are the synthetic units defined here; they are not currency or physical
hardware resource units. Each data stream is SHA-256-derived from a versioned
namespace, family, dimensions and replicate, using Julia 1.10.11 MersenneTwister.
Concrete matrices, bounds, rows and hashes are retained before solving.

- **Facility allocation:** nonnegative integer allocations `X[i,j]` and facility
  units `y[j] ∈ 0:h` minimize `vec(X)'A*vec(X) + f'y`. Rows enforce exact client
  demand, `sum_i X[i,j] ≤ c[j]y[j]`, and `X[i,j] ≤ d[i]y[j]`. Source order is
  client-major allocation followed by facility units. Draw `h ∈ 1:5`, demands
  uniformly from `1:200`, unscaled capacities from `500:1000`, per-unit capacities
  by rounding their division by h, and fixed costs from `500:1000`. A is the
  rounded symmetrization of independent uniform `[0,1)` entries. Retain loose
  declared allocation upper bounds `h*maximum(c)`. A need not be PSD. Total
  capacity gives an independent infeasibility screen or transportation witness.
- **Inventory/sales:** production `x ∈ 0:s` and sales `y ∈ 0:D` minimize
  `x'Hx + O'x − R'y`, with aggregate production ≤ s, aggregate sales ≤ D and
  `y[i] ≤ x[i]`. Draw D uniformly from `1:s-1`, O uniformly from `[0,1)`,
  R=round(1.1O), and H=`0.01ξ/s²*(U+U')/2`, with independent uniform ξ and U.
  H is unrounded, nonnegative and need not be PSD. This is an aggregate model;
  it is not a multi-period stock balance. At least one optimum has x=y because
  H and O are nonnegative; source validation does not replace the primary model
  with that reduction.
- **Route-count allocation:** `x[i] ∈ 1:m`, `y[j] ∈ 0:n`, with only
  `sum(y)=sum(x)`, minimize `x'Dx + T'x`. Draw T and U uniformly from `[0,1)`
  and D=`ξ/m²*(U+U')/2`. The fidelity profile rounds D and T. For all selected
  m≥4 this makes D zero. A separately labeled unrounded profile uses the SAME
  fresh draw and retains the quadratic objective. Both profiles are monotone:
  x=ones, y=(n,0,…,0) is globally optimal. This is not capacitated vehicle routing
  on a network, and the unrounded version is not evidence of a hard routing task.
- **Bounded quadratic knapsack:** `x ∈ 0:m` maximizes `x'Qx`, subject to
  `w'x ≤ floor(m*sum(w)/2)`. Draw an n×n integer matrix A uniformly from `1:9`
  and weights from `1:10`; `Q[i,j]=floor(sqrt((A*A')[i,j]/n))`, evaluated with
  integer square roots. Q is symmetric and nonnegative, with no PSD assumption.

The active-grid contract is:

| Family | n | m (or supply s) | Draws | Structural | Direct |
|---|---|---|---:|---:|---:|
| Facility | 5,10,20,25,30,50 | 4,8,10,16 | 3 | 72 | 12: n=5,10; m=4,8 |
| Inventory | 10,20,40,50,70,100,150,200 | 4,64,128,200,512,1024 | 3 | 144 | 144 |
| Route allocation | 10,20,40,50,70,100,150,200 | 4,64,128,200 | 3 | 96 | 96 |
| Knapsack | 5,10,15,20 | 5,10,15,20 | 3 | 48 | 48 |

Thus 360 underlying draws plus 96 paired unrounded route profiles give 456
structural profiles and 396 direct cases. Older nominal generator grids and a
later two-replicate knapsack solver invocation differ from retained experiment
coverage; this study uses all three replicates and the active grids above.

## Comparisons and interpretation

Six arms are native integers; radix with four levels; bounded four-level digits
with maximum weight 64; radix with two levels; pinned ToQUBO binary encoding of
the complete native target; and pinned ToQUBO binary encoding of the original
source with its own default penalty/GCD policy. The controlled binary arm
preserves native penalties; the default arm is a separate compiler-policy
comparison. Identical canonical targets are reported as aliases. Weight cap 64
was selected from expansion/resource considerations before measuring outcomes.

Every integer arm uses public compilation interfaces. Affine digit ownership and
complete native-interval coverage are checked independently. Hand-computable
integer/dyadic fixtures exhaustively check target optima against independently
enumerated source optima. Large Float64 energy comparisons are numerical
diagnostics, not exhaustive proofs. In particular, large penalties can obscure
small source terms through cancellation; feasible-lift discrepancies are retained.

Exact reformulation means global optima correspond under sufficient penalties;
it does not imply a bounded sampler always finds a global optimum. Gurobi is
used if the existing license works, otherwise SCIP is selected BEFORE results.
The backend is frozen and never silently substituted mid-campaign. Both solve
the original source model, with one thread, 300-second caps and recorded status,
bound, independent integrality/feasibility and objective audits. A time-limited
incumbent is not a certified optimum. Numerical solver optimality is distinct
from exact enumeration and the independent route monotonicity certificate.

The local knapsack analogue has 48 instances × six arms × three batches × ten
independent chains = 8,640 chains, reserving 4,000 proposals each (34,560,000 total).
Shared random source-coordinate starts avoid trivializing first feasibility with
a known feasible zero witness. The proposal kernel, temperatures, clocks, energy
scaling and seed contracts are explicit in `protocol.toml`. Terminal independent
reads (with observed and planned denominators kept separate), any-hit chains and best-visited diagnostics are separate. First-feasible
work and time include zero-hit censoring; correlated observations are not treated
as IID independent trials. Quality is source objective, never penalized energy.
Ratios to uncertified incumbents are labeled accordingly and can exceed one.

Canonical structural metrics shift lower bounds, remove fixed coordinates,
combine unordered couplers and fold binary squares into linear terms. Graph
density uses N(N−1)/2. Total widths, total true levels and maximum levels are
separate quantities. Spectral diagnostics use the same canonical symmetric
coefficient matrix; eigenvalue spacing is neither an optimization gap nor a
quantum gap. Undefined and numerically singular cases remain in the raw records.
Compilation timings include all applicable compiler stages and extraction, with
source construction separately reported and all arms warmed before measurement.
Timings are wall-clock observations on a shared host under one-CPU cgroups,
not exclusive-core measurements; separate low-memory diagnostic jobs can run
concurrently. Treat performance contrasts as descriptive.

## Execution and replay

Use Julia 1.10.11 with this profile's frozen Manifest. `setup.jl` installs its
pinned dependencies without re-resolution. The relative local package path also
loads the archived source during standalone replay. Run `runtests.jl` for bounded
validation; `TOQUIO_CHECK_GUROBI=true` additionally checks the existing license.
CI uses SCIP without credentials. Every heavy local command requires an OS memory
cap with no swap and finite timeout, including setup and validation.

`prepare.jl OUTPUT_DIRECTORY` writes all concrete inputs without solving.
`campaign.py` launches one memory/CPU-bounded Julia Docker worker from a clean
committed source snapshot and retained concrete inputs. The independent watchdog
caps compiler/spectral phases at 1,200/1,800 seconds respectively. A manufactured
18,656-variable binary layout compiled and completed its spectral check within
12 GiB, with observed cgroup peak 6,040,190,976 bytes. This resource calibration
is excluded from campaign outcomes; admission remains an estimate backed by
the hard OS limit. Both pinned ToQUBO policies also compiled a manufactured
16,208-variable layout, with controlled/default peaks 9,281,986,560 and
10,486,755,328 bytes respectively. Attempt markers prevent invisible retries after
interruptions. Every planned cell has a status; refused, errored and censored
cells remain in denominators and do not establish full execution. Source,
protocol, concrete-input, target-polynomial and projection hashes bind results.
Exclusive supervisor locking and confirmed shutdown of surviving task-owned workers
protect resume. Julia replay audits bind exact chain, polynomial and input bytes;
Python independently checks source points and all aggregate inputs.
Process logs and license configuration never enter the numerical export.

The measurement snapshot remains immutable. Reporting tools have a separate
clean commit, archived by `freeze_analysis.py REPOSITORY CAMPAIGN` under
`analysis-source/benchmarks/quadratic_case_study`; `analysis-files.json` binds
every tool byte and distinguishes the producing and postprocessing commits.
Run the retained reporting tools with `PYTHONDONTWRITEBYTECODE=1` so this source
inventory stays exact. `report.py CAMPAIGN OUTPUT` independently checks original
source equations and recomputes tables without solving or sampling. Its bounded
reader streams over unused expanded compiler metadata and releases diagnostics
that tables do not use. Every original raw cell byte remains in the packet.
`replay.jl CAMPAIGN [MAX_CHAINS]`
replays retained actual proposal counts with a nonbinding clock; elapsed
wall timestamps are not reproducible. `plots.py OUTPUT` plots verified tables.
The plot environment pins Python 3.13.5, matplotlib 3.10.9 and NumPy 2.5.0;
`plot-lock.txt` retains all exact distribution versions.

Measurement coverage and resource-protocol conformance are reported separately.
A live effective swap-limit discrepancy was observed and corrected during this
campaign, although Docker's configured limits stayed unchanged and swap use was
zero at the observations. Continuous no-swap enforcement cannot be certified
between those observations. The final packet retains the exact incident and a
conservative uncertainty window under `processes`. `resource_conformance.py`
reconstructs additive cell and chain associations from attempt/finish UTC
timestamps; every chain of a potentially overlapping cell is included because
chains have no separate UTC interval. The report, timing figures and regenerated
provenance tables carry this qualification. No original measurements are changed
or rerun. A retained incident without its hash-bound window is rejected.
Later cumulative usage evidence is retained separately from the original incident:
on this Linux 6.6 kernel, the read-only `memory.swap.peak` counter reports maximum
cgroup swap usage since creation ([kernel documentation](https://www.kernel.org/doc/html/v6.6/admin-guide/cgroup-v2.html#memory-interface-files)).
A hash-bound zero-peak observation can support no recorded cgroup swap use through
its conservative observation-start timestamp. It does not establish continuous
limit enforcement, host-wide swap inactivity, or coverage of the unfinished later
campaign. The report validates identity, timestamps, counter labels, hashes and
read-only kernel semantics before adding this later evidence.

Host-watchdog interruption and recovery are qualified separately from swap-limit
uncertainty. `supervision_conformance.py` verifies a hash-bound manifest of the
exact recovery records and executed controller sources under `processes`, then
associates cells and all their chains with the union of the conservative recorded
gaps. Intervening supervised time is not automatically included. Original worker
identity, unchanged measurement/protocol flags, retained phase timestamps and
controller handoff links are checked. The report and timing figures disclose that
continuous phase/campaign deadline enforcement during these gaps cannot be
certified; completed measurements do not establish full deadline conformance.
Missing, changed or unbound recovery evidence is rejected. No measurement is rerun.

Campaign packet schema 2 uses lossless XZ logical archives (preset 6) in ordered,
hashed parts of at most 48 MiB. The frozen 512 MiB limit applies to their aggregate
compressed bytes. A separate 64 GiB total uncompressed allowance and a free-disk
check with 1 GiB headroom bound extraction. The streaming decoder has a 128 MiB
memory allowance; member names, sizes, full SHA256 inventory, every part and the
logical archive digest are checked. Input archives retain schema 1 and their
original deterministic gzip bytes. Rebuilding reports uses the separately frozen
analysis source; Julia replay uses the original measurement profile.

The resource-only postprocessing amendment increases the original 32 GiB raw
allowance to 64 GiB after a bound-based forecast identified approximately 49 GB
of expanded diagnostics. It leaves the producing protocol and compressed budget
unchanged. Previous reporting snapshots and their manifests remain byte-identical
under `analysis-history`; `postprocessing-amendment.toml` records this amendment.
Packing has a six-hour ceiling; extraction has a two-hour ceiling. The original
636 MiB-cell diagnostic did not finish compression within 600 seconds at one
quarter CPU; that attempt is not reported as a successful roundtrip.

Use `pack.py extract-analysis PACKET BOOTSTRAP` to verify and extract the small
archived reporting closure. Then run its `pack.py extract PACKET VIEW --report-view`
with `PYTHONDONTWRITEBYTECODE=1`. This verifies every original archived byte while
omitting only unused cell metadata from a derived working view. It preserves the
original index and records original versus view hashes, revisions and projection
identity. Subsequent report verification checks this view and its extraction
provenance; original-byte verification happens during extraction. Inputs, source,
chains, polynomials, replay audits and history stay byte-identical. The view is
capped at 8 GiB, including its manifests, with 1 GiB additional free-disk headroom.
Use `report.py VIEW OUTPUT --require-report-view` to require its provenance even
if all view indicators were removed. Any remaining incomplete provenance or
changed view is rejected. A directory with all provenance removed cannot be
distinguished from raw data unless view mode is explicitly required. Write
reports outside the view directory.
Full raw extraction remains available without `--report-view` when disk permits.

No physical-provider jobs, uploads or paid sampling are part of this campaign.
Physical knapsack replication remains gated on the separate hardware contract,
precision, allocation and budget work. Local sampling is explicitly software.

For the Docker campaign, initialize its task-owned depot using the frozen
Manifest with this checkout mounted at `/workspace`:

```sh
docker run --memory 4g --memory-swap 4g --cpus 1 \
  --mount "type=bind,src=$(pwd),dst=/workspace,readonly" \
  --mount type=volume,src=toquio-dell-study-depot,dst=/depot \
  --env JULIA_DEPOT_PATH=/depot --env JULIA_NUM_THREADS=1 \
  --env OPENBLAS_NUM_THREADS=1 --env JULIA_NUM_PRECOMPILE_TASKS=1 \
  julia:1.10.11 timeout 600 julia --startup-file=no \
  --project=/workspace/benchmarks/quadratic_case_study \
  -e 'using Pkg; Pkg.instantiate()'
python3 benchmarks/quadratic_case_study/campaign.py start \
  --source . --output /tmp/fresh-quadratic-campaign --backend Gurobi
```

Select `--backend SCIP` when Gurobi is unavailable. The supervisor forwards only
existing Gurobi license configuration and freezes the chosen backend. Source must
be a clean committed checkout. Resume the same output directory with
`campaign.py resume --output /tmp/fresh-quadratic-campaign`; an interrupted
attempt is retained as interrupted and is not silently repeated. Use Python 3.11
or newer for the supervisor and report tools.
