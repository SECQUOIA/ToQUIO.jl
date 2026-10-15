# Changelog

## 0.2.0

- Add optional exact radix and bounded-weight integer encodings, configurable
  levels/weights and allocation limits, while retaining native encoding as default.
- Preserve original-variable and generated-slack decoding through composed maps;
  expose portable reformulation metadata and original-source feasibility checks.
- Add penalty offset/scale controls, explicit hints and applied-penalty inspection.
- Supply JuMP encoding examples, four seeded integer benchmark families, finite
  replay tools, frozen classical results and pinned offline QCI interoperability.
- Archive all 16 legacy examples' fixed-budget heuristic comparison, with complete
  raw evidence and generated tables. Distinguish search success from exactness;
  exhaustively verify every target of the documented simple ILP.
- Report the actual package version through MOI and invalidate cached metadata
  when Project.toml changes.

Julia 1.10 and MOI 1.11 remain supported. Root runtime dependencies remain
LinearAlgebra and MOI. Optional experiment dependencies stay isolated. Supported
models have finite integer domains, integer-affine constraints, and linear or
quadratic objectives; no continuous discretization or automatic strategy
selection is introduced. Archived experiments retain their original source and
environment pins. Live QCI validation remains pending and no general encoding
superiority or quantum advantage is claimed.

## 0.1.0

Initial registered release.

### Existing source corrections included in 0.1.0

- Solver-backed result queries now report original-model semantics:
  `MOI.VariablePrimal` maps source variables to target variables, and
  `MOI.ObjectiveValue` returns the original objective evaluated at those mapped
  values. Use `ToQUIO.PenalizedObjectiveValue()` to inspect the backend target
  objective with penalties and slack terms.
- Optimizer reformulation now maps source variables and constraints by their MOI
  list positions instead of raw index values, preserving correct target columns
  and constraint rows for non-contiguous source indices.
- `to_quio` now validates source models before reformulation: all source variables
  must be bounded integer or binary variables, affine constraint coefficients and
  right-hand sides must be integer-valued, equality and inequality rows must be
  feasible against variable bounds, equality rows must satisfy the integer
  divisibility condition, and custom constraint penalty hints must be positive.
