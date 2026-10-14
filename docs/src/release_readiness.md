# Release readiness and milestone acceptance

This is a software acceptance checklist and a version recommendation, not a
release announcement. The [roadmap](https://github.com/SECQUOIA/ToQUIO.jl/issues/45)
owns current progress and refreshes after each PR or external gate changes.
Use the [deliverable guide](deliverable.md) for pinned-source installation and
reproduction, and [CONTRIBUTING.md](https://github.com/SECQUOIA/ToQUIO.jl/blob/main/CONTRIBUTING.md)
for the actual registered Julia release procedure.

## Published versus development API

The latest GitHub release inspected for this preparation is
[v0.1.0](https://github.com/SECQUOIA/ToQUIO.jl/releases/tag/v0.1.0), tagged at
`0a9e956060ccd48bdc43ab79b11c9bf5877c85d5`. Its source does not contain the new
`NativeEncoding`, `RadixEncoding`, `BoundedEncoding`, `EncodingStrategy`,
`MaxEncodedVariables`, `lift_native_state`, `project_original_state`,
`reformulation_metadata`, `PenaltyOffset`, `PenaltyScale`, `is_feasible` and
`feasibility_report` interfaces described by the development guide.
Installing the tagged release therefore does not install these APIs. The
development tree's `version = "0.1.0"` field is not evidence that they have been
registered or tagged. A fresh registry installation must be checked separately
when a release is authorized.

## Proposed next release notes

- Add exact optional radix and bounded-weight integer strategies, configurable
  levels/weights and allocation limits, while retaining native encoding as default.
- Add composed decoding for originals, generated slacks and fixed coordinates,
  plus portable reformulation metadata and explicit original-source feasibility.
- Add penalty offset/scale controls and applied-penalty inspection.
- Supply public JuMP examples, four seeded integer benchmark families, finite
  replay tools, raw classical results and a pinned offline QCI readiness packet.
- Keep finite bounded integer/affine-constraint support explicit; continuous
  discretization and automatic strategy selection are not part of this release.

Recommend **0.2.0** for the next reviewed feature release. This is a proposal;
`Project.toml` is unchanged and no registration, tag, GitHub release or hosted
documentation deployment is performed by #54. Preserve Julia `1.10` and root
MOI `1.11` compatibility unless evidence from the minimum/current CI lanes
requires an explicit change. Root runtime dependencies remain LinearAlgebra
and MOI. JuMP lives in the examples environment; ToQUBO/HiGHS and QCIOpt remain
isolated research/interop dependencies with their own narrower pins.
When a 0.2.0 release is authorized, review/update ToQUIO compat in the docs,
examples, benchmark and hardware projects and rerun those profiles. Retain the
older pinned source/environments for immutable archived research reproduction.

Metadata schema v1 remains the native representation; explicit encodings use v2
with composed maps and the nested native snapshot. Consumers must accept the
documented schema or fail explicitly. Weight caps do not constrain final device
coefficient ranges. Heuristic/sample statuses and weak user penalties do not
certify original constrained optimality or feasibility.

## Acceptance checklist

| Gate | Evidence / remaining action |
|---|---|
| Merged foundations and strategies | PRs #55–#63 integrated into main; consult the current roadmap for subsequent merge identities |
| Corpus/classical research preparation | PR #63 merged after Astra review and green CI; #64 corrected a permutation tie error after Astra review; consult the roadmap for current integration evidence |
| Offline provider preparation | Astra reviewed PR #65; its provider-sample provenance finding is fixed; inspect current-head CI and obtain the required acceptance before integration |
| Public software examples and smoke replay | Separate environment and Julia 1.10/current CI; inspect completed checks for the exact proposed release source |
| Package regression suite | Full package CI, including minimum MOI; recheck the final integrated release tree |
| Documentation | Nondeploying build is source evidence; verify the published site after any separately authorized deployment |
| Classical raw-data reproduction | Pinned report/source/runtime, immutable archives and exact derived artifact comparisons |
| Live hardware evidence | Pending #53; disabled manifest is a proposal, mocks supply no physical results |
| Registered package | Pending authorization/version decision, Registrator acceptance, TagBot tag/release and a clean `Pkg.add("ToQUIO")` check |
| Hosted documentation | Published site must consume the intended release/main revision; a successful PR build is not deployment |
| Full research milestone | Remains open until approved live evidence is delivered or the project owner explicitly changes that milestone |

Before a later release, integrate dependent PRs in order and recheck their
current-head CI, reviews and source pins. Use merge commits to keep archived
reproduction revisions reachable, or explicitly retain/update the pins after a
different strategy. Build/test the actual release tree and follow CONTRIBUTING's
Registrator/TagBot procedure. Confirm clean registry installation contains the
intended APIs and verify served documentation; neither a version field nor an
open PR supplies that evidence.
