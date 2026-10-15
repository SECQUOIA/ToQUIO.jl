# Software release and research acceptance

ToQUIO **0.2.0** introduces the encoding, projection, metadata, penalty-control
and source-feasibility interfaces described in this manual. The older
[v0.1.0](https://github.com/SECQUOIA/ToQUIO.jl/releases/tag/v0.1.0), at
`0a9e956060ccd48bdc43ab79b11c9bf5877c85d5`, does not contain these interfaces.
A version field alone is not evidence of registration: the
[roadmap](https://github.com/SECQUOIA/ToQUIO.jl/issues/45) records dated publication
and installation verification, and [CONTRIBUTING.md](https://github.com/SECQUOIA/ToQUIO.jl/blob/main/CONTRIBUTING.md)
defines the Registrator/TagBot procedure.

## Installation and API availability

Use the Julia General registry, then inspect the version actually installed:

```julia
using Pkg
Pkg.add("ToQUIO")
using ToQUIO
@assert pkgversion(ToQUIO) >= v"0.2.0"  # Encoding feature release or later.
```

If an older registry snapshot resolves v0.1.0, update the registry and resolve
again; do not infer API availability from a local development checkout. For a
reproducible published feature version, request
`Pkg.add(name="ToQUIO", version="0.2.0")`.

## 0.2.0 changes

- Exact optional radix and bounded-weight integer strategies, configurable
  levels/weights and allocation limits; native encoding remains the default.
- Composed decoding for originals, generated slacks and fixed coordinates,
  portable metadata, and explicit source-feasibility checks.
- Penalty offset/scale controls and applied-penalty inspection.
- Public JuMP examples, four seeded benchmark families, finite replay tools,
  frozen classical evidence and a pinned offline QCI readiness packet.
- All 16 legacy examples' [local comparison](legacy_examples.md), with immutable
  raw results and a separate exhaustive simple-ILP exactness regression.
- MOI solver-version reporting follows the actual package version, including
  after version-only changes with a reused precompile cache.

Julia 1.10 and MOI 1.11 remain supported. Root runtime dependencies remain
LinearAlgebra and MOI. JuMP, ToQUBO/HiGHS and QCIOpt stay in separate maintained
environments. Those environments accept the 0.1 and 0.2 source lines; immutable
research archives retain the exact original environments and source revisions.

## Software versus hardware acceptance

The software comprises strategies, foundations, benchmarks, classical results,
offline adapters, documentation, exactness tests and reproducible examples.
Finite heuristic success is not an exactness certificate, and small local
comparisons do not establish general superiority or quantum advantage.

Historical classical replay checks reporting source
`209fcbaf1671ad49feeb1dae66e0997cc64dda36`. The schema-2 hardware packet replays
source `4ea46adcbaf619c0b5aa6a644d3d9de68e685e4a`. CI still tests the current
offline implementation separately. These pins preserve historical identity;
they do not claim the archived measurements used version 0.2.0.

Live hardware remains [#53](https://github.com/SECQUOIA/ToQUIO.jl/issues/53), with
provider-contract and supported-manifest acceptance in
[#52](https://github.com/SECQUOIA/ToQUIO.jl/issues/52). All proposed jobs remain
disabled until the actual device/precision/billing contract is confirmed and the
concrete subset/manifest/budget is approved. Source integration, successful CI,
registry publication and documentation hosting do not satisfy that research gate.
