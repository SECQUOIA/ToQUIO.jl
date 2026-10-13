# Penalty tuning

ToQUIO turns each supported affine constraint into a squared residual in the
QUIO objective. The native integer bounds remain constraints on the target.
These APIs describe this source tree; use its project environment for the
examples. Registered release availability follows the package's release tags.

## Defaults and controls

For each row, the unscaled sufficient magnitude is

```math
\rho_{\mathrm{auto}} = \Delta_{\mathrm{bound}}/\varepsilon^2 + \mathrm{offset}.
```

`Δ_bound` bounds the source objective's range over the finite variable box.
Affine terms give the exact range when each variable's coefficients are combined;
noncanonical duplicates and quadratic terms use conservative termwise bounds.
The residual sensibility `ε` is the smallest nonzero residual used by the bound;
current integer-valued affine coefficients and right-hand sides use `ε = 1`.
It is distinct from the direct call's additive `ϵ` keyword.

`PenaltyOffset` and `PenaltyScale` default to 1. Both must be finite and strictly
positive. An unhinted row receives `scale * ρ_auto`; a finite, positive
`ConstraintPenaltyHint` overrides that entire expression with its exact value.
Hints bypass both global controls. `AppliedPenalty` always returns a positive
magnitude; maximization subtracts the squared penalty from the source objective.

Given a feasible source problem, exact supported integer domains/slacks,
sufficient magnitudes and adequate numerical precision, a global target optimum
is source-feasible. This is a statement about global optimization. It does not
promise that every sample from a heuristic backend satisfies the constraints.
A scale below 1 or a hint below `ρ_auto` may sacrifice this sufficient bound.

ToQUIO warns once per equality/inequality kind if any automatically scaled row
falls below its unscaled sufficient magnitude; low hints warn individually.
Warnings indicate risk, not proof that the selected penalty will fail. For each
sample, check [`is_feasible`](@ref ToQUIO.is_feasible) or
[`feasibility_report`](@ref ToQUIO.feasibility_report) against the source model.

## Inspect equality and both inequality signs

This credential-free MOI example requires only ToQUIO's project dependencies.
It reformulates without solving. Each of the three penalties is 10 because the
objective box range is 9 and the default offset is 1. The snapshot records
constraints in equality, `<=`, then `>=` order. Typed identities distinguish
constraint indices with the same numeric ID.

<!-- penalty-example:inspection -->
```julia
using ToQUIO
import MathOptInterface as MOI

source = MOI.Utilities.Model{Float64}()
x, y = MOI.add_variables(source, 2)
for vi in (x, y)
    MOI.add_constraint(source, vi, MOI.Interval(0.0, 3.0))
    MOI.add_constraint(source, vi, MOI.Integer())
end
row(terms...) = MOI.ScalarAffineFunction(collect(terms), 0.0)
term(a, vi) = MOI.ScalarAffineTerm(Float64(a), vi)
MOI.set(source, MOI.ObjectiveSense(), MOI.MIN_SENSE)
MOI.set(source, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), row(term(1, x), term(2, y)))
eq = MOI.add_constraint(source, row(term(1, x), term(1, y)), MOI.EqualTo(3.0))
lt = MOI.add_constraint(source, row(term(1, x)), MOI.LessThan(2.0))
gt = MOI.add_constraint(source, row(term(1, y)), MOI.GreaterThan(1.0))

optimizer = ToQUIO.Optimizer(; penalty_offset = 1.0, penalty_scale = 1.0)
MOI.optimize!(optimizer, source) # Reformulates; no backend result is produced.
for (name, ci) in (("equality", eq), ("less than", lt), ("greater than", gt))
    println(name, ": ", MOI.get(optimizer, ToQUIO.AppliedPenalty(), ci))
end
metadata = ToQUIO.reformulation_metadata(optimizer)
for entry in metadata["constraint_encodings"]
    println(entry["source_constraint"], ": ", entry["applied_penalty"])
end
```
<!-- /penalty-example:inspection -->

For a JuMP `ConstraintRef con`, use
`MOI.get(backend(model), ToQUIO.AppliedPenalty(), index(con))` after `optimize!`.
In reformulation-only mode the high-level JuMP result getter can reject the query
because no solver result exists; the raw MOI query accesses the compiled value.

## Sweep and check a weak penalty

Here the source is `min 2x + 1`, subject to `x = 1`, with integer `x` in `0:3`.
The automatic magnitude is 7. We independently enumerate its known penalized
expression over four states, then check source feasibility with the public API.
The enumeration requires no backend or credentials; source feasibility is
evaluated from the original constraints.

<!-- penalty-example:sweep -->
```julia
using ToQUIO
import MathOptInterface as MOI

source = MOI.Utilities.Model{Float64}()
x = MOI.add_variable(source)
MOI.add_constraint(source, x, MOI.Interval(0.0, 3.0))
MOI.add_constraint(source, x, MOI.Integer())
f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(2.0, x)], 1.0)
MOI.set(source, MOI.ObjectiveFunction{typeof(f)}(), f)
MOI.set(source, MOI.ObjectiveSense(), MOI.MIN_SENSE)
ci = MOI.add_constraint(source,
    MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0), MOI.EqualTo(1.0))
optimizer = ToQUIO.Optimizer()
sweep = []
for scale in (0.1, 1.0, 2.0)
    MOI.set(optimizer, ToQUIO.PenaltyScale(), scale)
    MOI.optimize!(optimizer, source)
    penalty = MOI.get(optimizer, ToQUIO.AppliedPenalty(), ci)
    # Independently enumerate this model's known objective plus squared penalty.
    energies = [2value + 1 + penalty * (value - 1)^2 for value in 0:3]
    best = argmin(energies) - 1
    report = ToQUIO.feasibility_report(optimizer, [best]) # Equality has no slack.
    push!(sweep, (scale = scale, penalty = penalty, x = best, feasible = report["feasible"]))
end
foreach(println, sweep)
```
<!-- /penalty-example:sweep -->

| Scale | Applied magnitude | Best target x | Source feasible |
|---|---|---|---|
| 0.1 | approximately 0.7 | 0 | false |
| 1 | 7 | 1 | true |
| 2 | 14 | 1 | true |

For scale 0.1 the target prefers `x = 0`: its energy is 1.7 versus 3 at the
source-feasible `x = 1`. The source evaluator identifies the equality violation.
Generated slacks do not enter this equality-only example. For inequalities,
pass the full state including slacks; source violations and target slack
residuals are separate diagnostics, and no values are rounded or repaired.

## Hints and modification lifecycle

Set a hint before reformulation, for example
`MOI.set(backend(model), ToQUIO.ConstraintPenaltyHint(), index(con), 0.5)`
in JuMP. The [custom-penalty example](examples.md#Custom-Penalties) shows both
an equality and a greater-than row. To restore automatic selection, set the hint
to `nothing` where the source attribute storage supports it.

Changing offset or scale affects the next reformulation. Until it runs,
`AppliedPenalty` and metadata still describe the previous compile. Re-run
`optimize!` after changing controls or hints. Global controls survive
`MOI.empty!`; computed queries do not. Setting a global control to `nothing`
restores its default 1.

Direct `to_quio` calls use `ϵ` for the additive offset and `penalty_scale` for
the multiplier. These keyword controls follow the same hint precedence and
validation. See the [API reference](api.md#Automatic-Penalty-Controls) and
[algorithm derivation](algorithm.md#Penalty-Coefficient-Computation) for details.
