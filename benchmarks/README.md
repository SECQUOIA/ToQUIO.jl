# CQT protocol v1 experiment environment

These repository scripts implement issue #50. They generate the frozen four-family
corpus, validate the five compiler arms, run a bounded integer Metropolis control,
and archive replayable evidence. They are an experiment, not a production optimizer
or a physical device model. A smoke run does not establish performance conclusions.
The bounded comparison and statistical report belong to issue #51.

Use Julia 1.10 or newer from this source checkout. The separate environment pins
ToQUBO to `69ac52592f4c47ed2168bf480c9947d1fcbbfc2c` and HiGHS.jl to 1.26.0. It
does not change ToQUIO's runtime dependencies or MOI 1.11 compatibility floor.

```sh
julia --project=benchmarks benchmarks/setup.jl
systemd-run --user --scope --quiet \
  -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 \
  timeout 3600 julia --project=benchmarks benchmarks/run.jl smoke /tmp/cqt-smoke
```

The runner verifies Linux cgroup v2 resident-memory/no-swap limits and Julia/BLAS
threads before compiling. HiGHS receives one thread, seed777, zero relative and
absolute MIP gap, and a 10-second limit per generated source. Its solver status
and objective bound are numerical evidence; an incumbent is never called an exact
optimum. Pilot references are exhaustive original-box certificates.

`smoke` validates four pilots across five arms/two regimes and executes exactly
the 40 frozen warmup starts, reserving 5120 proposals. `preflight` additionally
validates all twelve generated models and every cap, with zero sampler starts.
`campaign` executes warmup, pilot, tuning and evaluation: 680 starts and 5,325,120
reserved proposals. Do not use smoke output as a completed campaign. Use a fresh
output directory for each mode; never overwrite old evidence.

All instances and executable hashes are frozen before references or compilation.
The archive contains its protocol, resolved dependency environment, references,
actual emitted maps, raw/canonical polynomials, penalty policies, preprocessing,
preflight results, seeded run order, source observations, ordered samples with
multiplicity, censoring/status/error records, and timing boundaries. Big integers
outside TOML's machine range and absent metadata use explicit tagged values.

Rerun the same command to resume within the original one-hour allowance on the
same monotonic clock origin. Reservations remain spent. An interrupted reserved
job becomes an invalid planned run with failure scores; it is not sampled again.
Completed jobs are read by deterministic keys. Crashed references and failed
preflight stop an incomplete campaign. Invalid/missing trajectories remain in
the all-planned denominator. No complete-campaign aggregate is produced here.

Replay an archived valid trajectory without importing ToQUBO or HiGHS:

```sh
julia --project=. benchmarks/replay.jl /tmp/cqt-smoke JOB_SHA256_KEY
```

Replay requires matching archived Julia, protocol and executable source hashes.
It uses the original reserved temperature budget and archived completed work,
checks full versus incremental energies and #34 source feasibility, and compares
initial/final states, ordered samples, multiplicities and move counts. It cannot
recreate elapsed times or wall-clock censoring from a seed. Run it under the same
OS memory cap and an outer timeout when checking supplied archives.

The corpus uses integer quantity/cost units and repository-authored MPL-2.0 data:

| Family | Exact variant and fixed draw order |
|---|---|
| Knapsack | Bounded integer quantities; item weights, then profits, in item order. Capacity is floor(45/100 times total available weight). |
| Facility | Single-source capacitated location with binary opens/assignments. Shipments equal integer demand times assignment. Draw client demands, facility fixed costs, then row-major per-unit shipping costs. Round-robin assignments give capacities equal to witness load plus one. |
| Inventory | Integer production/stock and binary setups, period balances and terminal stock zero. Draw demands, setup costs, production costs, in period order. Holding cost is one per stored unit. |
| CVRP | Directed binary arcs, integer cumulative loads and MTZ capacity rows. Draw demands, then each customer's x/y coordinates; use Manhattan costs. Round-robin routes supply the independent capacity witness. |

Concrete pilot boxes have 6/64/324/256 assignments and optima 5/6/5/4. Generation
never uses a competing arm or modifies a seed after observing results. Replay uses
archived concrete instances, not a promise that a future RNG reproduces them.

Controlled ToQUBO cells compile the complete native QUIO polynomial. Default cells
compile the original source with the pinned policy, preserving GCD normalization,
removed rows and nonnegative residuals left linear. The `toqubo_bounded_shim` is
disclosed repository code using the pinned binary allocator; upstream `Bounded`
is not used. Exact gates inspect emitted maps, independently convolve reachable
values, compare all canonical polynomial coefficients, test seeded digit states
and reference lifts, and enumerate full pilot targets under the shared budget.

The QUIO timing adapter calls the source-pinned post-native transform also used
by public `MOI.optimize!`; integration checks compare both routes. Source build,
native reformulation, encoding/copy, target extraction and metadata capture are
timed separately. Reports distinguish dense storage, logical couplers and process
high-water RSS from unmeasured physical resources. Backend/reference solve and
instrumented sampling/observation times have separate fields.

Preflight build costs include first-call JIT. After all pilot sampler warmups,
the runner measures warm builds again and verifies identical maps/polynomials.
Native setup is shared once per instance and is not summed across arms. Measured
run records sum shared native setup, the arm's own build and solve/observation.

No compatible archived campaign framework was recovered in the protocol's bounded
provenance search. These small scripts reuse the existing compiler, metadata and
feasibility APIs. They add no private dependency, commercial solver or credentials.
Provider roundtrips and live submissions remain issues #52 and #53.
