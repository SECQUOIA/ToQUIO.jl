# Exact integer encoding interface

The default `NativeEncoding()` keeps the existing reformulation and result path.
An optional strategy transforms the **already penalized** native model; it never
recalculates source penalties or adds digit-enforcement penalties.

The forward path is source → native QUIO and slacks → affine integer digits →
backend indices. Result access follows the composed maps back to source values.

Select a strategy with `Optimizer(; encoding=strategy)` or
`MOI.set(optimizer, EncodingStrategy(), strategy)`. Direct
`to_quio(T, varmap, conmap, source; encoding=strategy)` uses the same transform.
The global strategy applies to original variables and generated slacks. Its
`variable_encoding` hook receives typed source identities and a role, so an
extension may choose a different layout for a particular source variable or
slack. There are no separate per-variable/slack MOI settings in this interface.
Parameters live in the strategy object and its provenance descriptor.

The production radix and bounded-weight strategies are separate work items
(#48/#49). This page's small strategy only demonstrates the extension point.
No solver, hardware driver, continuous discretization or automatic selection is
included.

## Exact local maps and quadratic convention

Each native interval uses integer endpoints `L=ceil(l)` and `U=floor(u)`.
An extension returns `IntegerVariableEncoding(L, weights, upper_bounds)`, with
positive integer weights and active digit upper bounds; digits have lower bound
zero. Empty vectors represent a fixed coordinate. Checked integer arithmetic
verifies contiguous coverage and requires the image to equal `L:U` exactly.
The compiler rejects empty native intervals, gaps, wrong endpoints and integers
that lose precision in the coefficient type. Nonunique representations are valid.

For the full native state `z=[x;s]=a+B*d` and native polynomial
`z'G*z+g'z+gamma`, the target is

```math
G_d=B^TGB,\quad g_d=B^T(g+(G+G^T)a),\quad
\gamma_d=a^TGa+g^Ta+\gamma.
```

This includes offsets, fixed variables, cross terms and the constant even when
G is nonsymmetric. MOI diagonal terms have coefficient `2G_ii` and each unique
off-diagonal term has coefficient `G_ij+G_ji`. The objective sense and the selected
positive native `rho` are retained. Floating arithmetic still has the precision
of the chosen coefficient type; reject nonfinite transformed coefficients and
validate numerical parity for applications requiring tight tolerances.

`max_encoded_variables` / `MaxEncodedVariables()` defaults to 256 and checks the
complete digit count before dense expansion matrices are allocated. This is a
configurable allocation guard, not a verified device limit. It does not restrict
the default native path. Extensions must also bound their own layout construction;
the hook receives identities, not authorization to perform expensive experiments.

## A credential-free extension example

Activate/instantiate the repository project to run this example. The namespace
alias below uses ToQUIO's existing MOI dependency. The demonstration supports only
interval widths 0–2 and can be used for original variables and slacks.

```@example integer_encoding
using ToQUIO
const EMOI = ToQUIO.MOI

struct DemoPair <: AbstractIntegerEncoding end
function ToQUIO.variable_encoding(::DemoPair, lower, upper; context)
    width = upper - lower
    0 <= width <= 2 || throw(ArgumentError("DemoPair supports only widths 0–2."))
    IntegerVariableEncoding(lower, ones(Int, Int(width)), ones(Int, Int(width)))
end
ToQUIO.encoding_descriptor(::DemoPair) = Dict("name" => "demo-pair", "max_width" => 2)

source = EMOI.Utilities.Model{Float64}()
x = EMOI.add_variable(source)
EMOI.add_constraint(source, x, EMOI.Interval(-1.0, 1.0))
EMOI.add_constraint(source, x, EMOI.Integer())
f = EMOI.ScalarAffineFunction([EMOI.ScalarAffineTerm(2.0, x)], 3.0)
EMOI.set(source, EMOI.ObjectiveSense(), EMOI.MIN_SENSE)
EMOI.set(source, EMOI.ObjectiveFunction{typeof(f)}(), f)
# Use an affine row to demonstrate a generated slack.
row = EMOI.ScalarAffineFunction([EMOI.ScalarAffineTerm(1.0, x)], 0.0)
EMOI.add_constraint(source, row, EMOI.LessThan(0.0))
optimizer = ToQUIO.Optimizer(; encoding=DemoPair())
EMOI.optimize!(optimizer, source)
snapshot = reformulation_metadata(optimizer)
native_point = [-1, 1]
digits = lift_native_state(optimizer, native_point)
@assert project_native_state(optimizer, digits) == native_point
@assert project_original_state(snapshot, digits)[x.value] == -1
@assert is_feasible(optimizer, digits)
@assert snapshot["schema_version"] == 2
(digits=digits, source=project_original_state(optimizer, digits))
```

## Results, feasibility and saved maps

`MOI.VariablePrimal(result)` follows source → native → digit → backend maps.
Fixed source values are restored even with no allocated digit, but still require
a valid backend result index. `MOI.ObjectiveValue` evaluates the original source
objective; `PenalizedObjectiveValue` reports the backend's actual target objective.
Encoded MOI primal values use the optimizer coefficient type when conversion is
lossless, including fixed coordinates. Wider decoded values are retained when
conversion would round or overflow; explicit projection helpers also retain exact
or widened values. Noncontiguous source indices and remapped backend indices are
supported.

Large-magnitude sums of integer offsets/weights and hardware floating digits
(`Float16`, `Float32`, `Float64`) use an exact dyadic accumulator and return a
`BigFloat` with enough significand bits when ordinary arithmetic would lose an
integer-scale increment. This is independent of Int/BigInt storage. BigFloat
samples use their normal arithmetic precision; transformed polynomial coefficients
still use the compiler coefficient type as described above.

`project_original_state` and `project_native_state` accept a full encoded vector
in the recorded target order. They preserve fractional samples without rounding
or repairing them; malformed lengths, nonfinite values and decoding overflow are
rejected. `lift_native_state` is a deterministic right inverse for native integer
points within their bounds. It is not a repair of invalid samples. Duplicate digit
representations affect sampling multiplicity and neighborhoods, not decoding.

The existing `violations`, `is_feasible` and `feasibility_report` evaluate captured
original constraints after composed decoding. Slack residuals use the decoded
native slack values and remain separate from original feasibility. A fractional
or invalid target digit state can decode to a feasible source point; source
feasibility is not a certificate of digit-domain validity or target consistency.
Saved metadata contains maps, not source functions, so it cannot independently
perform source-feasibility evaluation. Multi-result point/status rules are
unchanged; nonpoint records are not silently treated as feasible samples.

| Raw data | Meaning with optional encoding |
|---|---|
| `:n, :Q, :L, :c, :l, :u, :rho, :D` | Original native polynomial, bounds and unchanged penalties |
| `:source_to_target_variables, :target_variables, :quio_variables, :slack_variables` | Legacy native coordinate identities; never replaced with multi-digit values |
| `:native_model` | The native model whose coordinates those keys describe |
| `:encoded_variables, :encoded_n, :encoded_Q, :encoded_L, :encoded_c, :encoded_l, :encoded_u` | Actual encoded target order, polynomial and bounds |
| `:target_to_backend_variables` | Actual target-to-backend map, populated when a backend is used |

Native metadata remains **version 1**. Optional encoding uses **version 2**:
`target_variable_order` and bounds describe actual digits, `original_variables`
contains the composed source maps, `auxiliary_variables` lists slack-owned digits,
and `native_variables` records all native affine expansions and typed slack
ownership. The complete version 1 snapshot, including penalties and canonical row
signs, is nested in `native_reformulation`. Fixed native coordinates still have
entries with constant expansions. Unknown/malformed schemas, shared or unowned
digits, wrong native coverage, forged source compositions and wrong slack owners
are rejected. Use a serializer that preserves the snapshot's numeric precision.

Strategy and allocation settings persist across `empty!` and apply only to the
next reformulation. Setting either MOI attribute to `nothing` restores its default.
A failed transformation clears current mappings before any backend solve.
Retained metadata snapshots remain independent of later settings changes.

## Extension and selection API

```@docs
ToQUIO.AbstractIntegerEncoding
ToQUIO.NativeEncoding
ToQUIO.IntegerVariableEncoding
ToQUIO.variable_encoding
ToQUIO.encoding_descriptor
ToQUIO.EncodingStrategy
ToQUIO.MaxEncodedVariables
ToQUIO.project_native_state
ToQUIO.lift_native_state
```
