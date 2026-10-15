# CQT software deliverable

This guide connects the exact integer encodings, public examples and recorded
experiments. Development source is pinned at `06f75e20338c5471ebb739c6cf88b88c38da02ce`.
The dependency order and current acceptance state are maintained in the
[roadmap](https://github.com/SECQUOIA/ToQUIO.jl/issues/45).

## Choose an encoding

| Strategy | Selection | Effect |
|---|---|---|
| Native identity | `NativeEncoding()` | Default; retains native variables, domains and generated slacks |
| Bounded-tail radix | `RadixEncoding(; levels=4)` | Exact affine digits with at most four values per digit |
| Bounded weights | `BoundedEncoding(; levels=4, max_weight=2)` | Exact affine digits with weights at most two; may add variables/couplers |
| Binary special case | `RadixEncoding(; levels=2)` | Exact binary digits; distinct from a separately implemented binary compiler |

Pass the strategy to `ToQUIO.Optimizer(; encoding=strategy)` and construct a
JuMP `Model(() -> optimizer)`. Parameters describe an encoding, not a verified
device capability. Native applied penalties remain unchanged across strategies.
The weight cap does **not** cap final quadratic or linear coefficients: source
coefficients, offsets, weight products and penalties also contribute.

The [common interface](encoding.md), [radix construction](radix.md) and
[bounded construction](bounded.md) explain exact coverage, fixed coordinates,
representation multiplicities, allocation guards and numeric representability.
Use the [penalty guide](penalties.md) for global offset/scale, user hints and
applied-penalty inspection; weak overrides require explicit source feasibility
checks. This guide does not introduce a second penalty convention.

## Worked JuMP example

`docs/examples/encoding_choices.jl` compares the strategies on

```math
\min x^2+3x+5+2y-z,\quad -2\le x\le8,\quad y\in\{0,1\},\quad z=2,
\quad x+y\le6,
```

with integer x and z. The example explicitly selects default penalty controls
and invokes reformulation-only optimizers. At the independently chosen feasible
point `x=-1, y=0, z=2`, the inequality slack is 7 and the source objective is 1.
All strategies lift and decode this point exactly, preserve the same penalties,
and evaluate the target polynomial to 1. A capacity-violating point remains
infeasible under original-source checks.

| Arm | Target variables | Maximum target levels | Minimum nonzero coefficient magnitude | Maximum coefficient magnitude |
|---|---:|---:|---:|---:|
| Native | 4 | 11 | 1 | 2316 |
| Radix, levels 4 | 7 | 4 | 193 | 12356 |
| Bounded, levels 4 / weight 2 | 7 | 4 | 193 | 6178 |
| Radix, levels 2 | 9 | 2 | 193 | 12356 |

The script also prints actual minimum/maximum nonzero polynomial coefficients
and their ratio using MOI's half-diagonal convention. The two four-level arms
use the same variable count here; weight cap two halves the largest literal
coefficient relative to radix, while the final magnitude remains far above two.
These are coordinate-dependent target coefficients before a provider's domain
shift: native retains negative/fixed coordinates, while encoded coordinates
start at zero and omit fixed digits. Actual device payloads need a separate audit.
These measurements are specific to this model and
are not solve-time or quality measurements. See [the bounded structural
measurement](bounded.md) for additional
coefficient and multiplicity tables with explicit finite enumeration budgets.

`lift_native_state` includes source coordinates and generated slacks in native
order. `project_native_state` restores that full state; `project_original_state`
returns source coordinates, including fixed values, keyed by MOI variable indices
for a live optimizer and integer source IDs for portable metadata. Use `is_feasible` or
`feasibility_report` on the optimizer to evaluate captured source constraints.
Portable metadata contains decoding maps, not the source functions required to
certify feasibility. Backend sample status and original-model feasibility are
separate facts.

## Install and run the public examples

Clone the explicit development revision rather than relying on the version field
or a moving default branch:

```bash
gh repo clone SECQUOIA/ToQUIO.jl /tmp/toquio-deliverable
git -C /tmp/toquio-deliverable checkout --detach 06f75e20338c5471ebb739c6cf88b88c38da02ce
cd /tmp/toquio-deliverable
```

`docs/examples/Project.toml` pins JuMP 1.32.1 and MOI 1.54.0, isolated from package
runtime and research dependencies. On Linux, apply the same 4 GiB/no-swap,
one-CPU/thread envelope to
setup and execution. A supported container can enforce equivalent limits when
the user systemd bus is unavailable.

```bash
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 \
  timeout 900 julia --project=docs/examples docs/examples/setup.jl
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 \
  timeout 300 julia --project=docs/examples docs/examples/runtests.jl
```

These commands need no provider credentials or backend solver. CI resolves this
separate environment and executes the examples on Julia 1.10 and current Julia.
Package tests and the nondeploying documentation build remain separate checks.

## Tiny portable replay

Create a 32-proposal native pilot smoke record, then replay it in a separate
process using the same checked-out source and resolved environment:

```bash
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 \
  timeout 120 julia --project=docs/examples docs/examples/tiny_replay.jl create /tmp/cqt-tiny
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 \
  timeout 120 julia --project=docs/examples docs/examples/tiny_replay.jl replay /tmp/cqt-tiny
```

Creation refuses an existing directory. The manifest binds executable source,
example script, protocol, Julia/MOI versions, cell and trajectory hashes. Replay
checks the ordered states, move counts, source observations, best feasible point
and hit proposal indices. Wall-clock measurements are retained but not reproduced.
The pilot witness is a feasible reference for this smoke check, not a new optimum
certificate or performance study. Tampered records fail hash validation. Create
and replay in the same runtime; a record created on another Julia/MOI version is
intentionally rejected.

## Reproduce the recorded research

| Artifact | Source/dependency identity | Location and command |
|---|---|---|
| Four-family corpus and runner | Protocol v1; sampler/compiler revision `2a4f1809ebcc148748f57a8fb2772eca3899e1bb` | [Benchmark guide](benchmarks.md), `benchmarks/README.md` and `protocol_v1.toml` |
| Frozen classical campaign | Julia 1.10.11, MOI 1.54.0; ToQUBO `69ac52592f4c47ed2168bf480c9947d1fcbbfc2c`; HiGHS.jl 1.26.0 | `benchmarks/results/protocol_v1/campaign.tar.gz`, hashes in `checksums.json` |
| Paired descriptive report | Reporting revision `209fcbaf1671ad49feeb1dae66e0997cc64dda36` and three script hashes | [Classical report](classical_study.md) reproduction commands; [generated tables](TABLES.md) |
| Offline QCI packet | QCIOpt `c3c3ed9e1b27150b3b39c9e98807007daf3f7a01`, MOI 1.54.0; source file hashes | [Hardware readiness](hardware.md), `benchmarks/hardware/results/` and its exact reproduction command |

The completed campaign has 680 valid records, including retained clock-censored
trajectories. Reproduction reads those immutable records; it does not repeat or
retune the campaign. Statistical intervals are descriptive, with missing gap
pairs and calibration repeats disclosed. Radix and bounded targets alias on six
of eight instances. No general superiority or quantum advantage is established.

The four-family hardware packet is post hoc, nonrepresentative and favorable in
composition. Every proposed live job remains disabled; offline mocks are not
hardware evidence. All twelve candidates fail the stated conservative precision
screen, and native knapsack also exceeds its conservative level screen. Provider
confirmation, explicit subset acceptance, account access and a concrete approved
manifest/budget are required by [#53](https://github.com/SECQUOIA/ToQUIO.jl/issues/53).

See [release readiness](release_readiness.md) for release notes,
compatibility and the milestone checklist. No package release or live campaign
is implied by source-pinned installation or successful CI.
