# Replaying the CQT benchmark corpus

The repository's `benchmarks/` scripts implement the four-family protocol and
archive inputs and trajectories for independent replay. The native, radix,
bounded, pinned binary and disclosed bounded-binary shim arms use the same
concrete source instances. Software validation and smoke runs do not establish
comparative performance or hardware capability.

The source pilots can be checked using only the ordinary package environment:

```@example cqt_corpus
using ToQUIO
include(joinpath(pkgdir(ToQUIO), "benchmarks", "CQTBenchmarks.jl"))
[(i.id, CQTBenchmarks.exact_reference(i)["objective"])
 for i in CQTBenchmarks.corpus(CQTBenchmarks.PROTOCOL) if i.stage == "pilot"]
```

The exact optima are 5, 6, 5 and 4 for knapsack, facility, inventory and CVRP.
Quantity and cost units are integers. Facility shipments are demand times a
binary assignment; inventory production/stock and routing loads are integer
variables. None is a continuous variable silently discretized for this study.

Use the separate optional environment for the actual ToQUBO/HiGHS integrations:

```sh
julia --project=benchmarks benchmarks/setup.jl
systemd-run --user --scope --quiet \
  -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 \
  timeout 3600 julia --project=benchmarks benchmarks/run.jl smoke /tmp/cqt-smoke
```

The smoke performs all pilot compiler gates and the 40 frozen warmup starts.
`preflight` also checks twelve generated models and every tuning cap. `campaign`
uses the full frozen 680-start budget; its performance report is separate work.
Every source/reference/compiler input is hashed before sampling. Failed preflight
stops the campaign, and timeouts/invalid planned runs remain visible in the ledger.

Resume by invoking the same mode/output again. Spent reservations are never
replenished, and an interrupted job is retained as invalid rather than resampled.
Use a new output directory for different modes, source/runtime hashes or settings.

For a completed job key listed in `ledger.toml`:

```sh
julia --project=. benchmarks/replay.jl /tmp/cqt-smoke JOB_SHA256_KEY
```

Instantiate the ordinary root environment and align its MOI version with
`manifest.toml`'s `replay_moi_version` as described in `benchmarks/README.md`.
Replay needs matching source hashes and the archived Julia/MOI versions. It reconstructs
the original proposal schedule up to completed work and checks ordered samples,
multiplicities, energies and source feasibility. Clock timings stay archived;
seeds do not reproduce wall-clock censoring. Use an OS memory cap and timeout for
replay too. Raw/canonical coefficient ranges and couplers describe logical models;
they are not device-range or embedding certificates.

Read `benchmarks/README.md` for draw order, provenance, timing scopes and archive
semantics. The [frozen study](study.md) specifies quality targets, tuning, failure
scores and statistics. No credentials or live submissions are part of these scripts.
