# Changelog

## Unreleased

### Changed

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
