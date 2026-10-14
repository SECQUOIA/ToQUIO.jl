# Offline QCI interoperability

This isolated experiment environment uses QCIOpt 0.2.0 source revision
`c3c3ed9e1b27150b3b39c9e98807007daf3f7a01`, with every imported driver/client
source file bound in `qci_source_pin.json`. This is a development pin, not a
claim that the revision is in the v0.2.0 tag. ToQUIO's runtime dependencies do
not include QCIOpt or its CondaPkg/PythonCall environment.

`offline.jl` calls the actual driver's network-free load, request construction,
response parsing and result reconstruction entry points. It never calls
`optimize!`, allocation queries, uploads or job submission. Tests cover unequal
integer bounds, fixed coordinates, mixed domain widths, both objective senses,
constants, MOI's diagonal convention, composed source decoding, multiplicities,
missing timing, failed provider statuses, and invalid samples. Mock provider
energies are retained separately from locally reconstructed target and source
objectives. Neither a mock sample nor a provider COMPLETED status certifies
optimality or original constrained feasibility.

Only allowlisted identifiers, numerical timing, local configuration and audited
samples are persisted. Unknown response fields and raw diagnostic text are
omitted. Missing timing remains `unavailable`; it never becomes a zero duration.

## Reproduce

Use Julia 1.10.11 and the pinned MOI 1.54.0 environment. Download the public driver
through `gh`, extracting into an empty scratch directory with Python 3.11.4+:

```bash
gh api repos/SECQUOIA/QCIOpt.jl/tarball/c3c3ed9e1b27150b3b39c9e98807007daf3f7a01 > /tmp/qci-source.tar.gz
mkdir /tmp/qci-source
python3 -c 'import tarfile; tarfile.open("/tmp/qci-source.tar.gz").extractall("/tmp/qci-source", filter="data")'
```

Pass the extracted `SECQUOIA-QCIOpt.jl-*` directory to `setup.jl`. Keep the
driver's default CondaPkg backend; an optional `JULIA_CONDAPKG_ENV` points it at a
scratch directory. No token is needed. For every Julia invocation below, apply
the same 4 GiB/no-swap scope, one CPU/thread and finite timeout used by CI:

```bash
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env -u QCI_TOKEN -u QCI_RUN_LIVE_TESTS JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  JULIA_NUM_PRECOMPILE_TASKS=1 timeout 900 julia --project=benchmarks/hardware \
  benchmarks/hardware/setup.jl /tmp/qci-source/SECQUOIA-QCIOpt.jl-c3c3ed9
python3 benchmarks/check_study_artifacts.py extract benchmarks/results/protocol_v1 /tmp/cqt-campaign
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env -u QCI_TOKEN -u QCI_RUN_LIVE_TESTS JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  JULIA_NUM_PRECOMPILE_TASKS=1 timeout 300 unshare --user --map-root-user --net \
  julia --project=benchmarks/hardware benchmarks/hardware/test_offline.jl
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% \
  env -u QCI_TOKEN -u QCI_RUN_LIVE_TESTS JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  JULIA_NUM_PRECOMPILE_TASKS=1 timeout 300 unshare --user --map-root-user --net \
  julia --project=benchmarks/hardware benchmarks/hardware/prepare.jl /tmp/cqt-campaign /tmp/cqt-hardware
python3 benchmarks/hardware/check_packet.py benchmarks/hardware/results /tmp/cqt-hardware
```

Setup downloads software dependencies. The test and preparation processes run
inside a Linux network namespace with no external connectivity. Platforms that
cannot create this namespace can inspect the packet or use the Linux CI result;
they must not claim the same network isolation from an unrestricted invocation.

## Device contract and limits

The [QCI developer guide](https://quantumcomputinginc.com/learn/module/introduction-to-dirac-3/dirac-3-developer-beginner-guide)
defines minimization, zero-based integer values configured by level counts,
one-based sorted term indices with zero padding, omitted constants and an API
total-level ceiling of 949. Actual account allocation is a separate prerequisite.
The pinned driver distinguishes free/paid totals of 500/949; this packet uses 500
conservatively without querying an account.

The [Dirac-3 user manual v0.0.4, sections 4.2 and 4.4](https://assets.ctfassets.net/i1dyhzbyi8ad/55XZTIVzzgNorw3OT6SrLF/f728a6ac69c41900bd9344cb36c96008/Dirac_3_Users_Guide_v0_0_04.pdf)
describes bounded integer values near 16 and an effective coefficient dynamic
range near 200:1. The upper-bound/number-of-values wording requires provider
confirmation. This campaign screen conservatively limits each variable to 16
levels, flags singleton domains, coefficient ratios above 200 and distinct
coefficient separation below maximum magnitude/200. These are local admission
rules, not a hardware accuracy certificate. Digital acceptance does not prove
analog fidelity. A uniform scale cannot improve coefficient ratios. The packet
records **no normalization or quantization**; it preserves the frozen polynomial
and penalties. Unsupported payloads are explicitly refused by
`require_conservative_payload`; preparation retains their reasons for review.

## Manifest and human gates

`results/candidate_manifest.toml` names 12 target candidates, three repeats each,
ten reads per job, relaxation schedule 1 and zero automatic retries: at most 36
attempts and 360 reads. Every job is disabled. A 60-second per-job device-usage
scenario totals 2,160 seconds; it is a proposed allocation ceiling, not a measured
charge or an enforceable provider timeout. The account owner must establish an
actual device-time bound, allocation or price and approve the concrete budget
before #53. Unexpected billing or any failed/invalid result stops execution.

The source packet from #51 is post hoc, nonrepresentative and favorable in
composition. It is retained for a potential demonstration only. A maintainer must
explicitly accept this purpose/subset or authorize a revised manifest; comparative
or advantage claims are barred. Passing a payload screen leaves provider contract,
account access, precision and manifest/budget approval unverified.

QCI is the sole proposed route. D-Wave/IBM are excluded from this manifest and
have zero jobs: they need an appropriate binary QUBO adapter, export/replay fixture,
owner and access approval before inclusion. Binary exports do not make them native
QUIO backends. Upstream driver fixes require work in their owning repository.
