# Changelog

## Unreleased

### Changed

- `to_quio` now validates source models before reformulation: all source variables
  must be bounded integer or binary variables, affine constraint coefficients and
  right-hand sides must be integer-valued, equality and inequality rows must be
  feasible against variable bounds, equality rows must satisfy the integer
  divisibility condition, and custom constraint penalty hints must be positive.
