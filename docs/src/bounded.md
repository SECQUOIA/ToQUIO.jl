# Exact bounded-weight integer encoding

Select `BoundedEncoding(; max_weight=2, levels=4)` through the
[common interface](encoding.md). The global default remains `NativeEncoding()`.
The strategy applies to originals and generated slacks and records both caps,
the allocation limit and every actual affine map in schema version 2 metadata.
Strategy identity uses `name`, `construction` and the recorded parameters
together, plus the compiler revision for replay. Radix and bounded intentionally
share the bounded-tail construction identifier; their names and caps distinguish
the arms. Consumers must not key an arm on `construction` alone.
It preserves the already selected native penalties without adding enforcement
penalties. Strategy composition can use the interface's per-coordinate context.

## Construction and guarantees

For integer endpoints `L=ceil(l)`, `U=floor(u)` and width `W=U-L`, start at
coverage `C=0` and repeatedly append

```math
w=\min(C+1,W-C,\mu),\qquad
m=\min(\mathrm{levels}-1,\lfloor(W-C)/w\rfloor),\qquad C\leftarrow C+wm,
```

where `mu=max_weight` is a positive integer. The source coordinate is
`L+sum(w_j*d_j)`, with integer digits `0<=d_j<=m_j`.
Each weight is at most mu and each digit has at most `levels` values.
Since `w<=C_old+1`, translated reachable intervals touch or overlap, so coverage
stays contiguous. Since `w<=W-C_old` and both caps are valid, `m>=1` and progress
is positive. The endpoint never exceeds W and ends at W exactly. Every permitted
digit assignment stays within the source interval, and every source integer has
a preimage. Negative/shifted intervals retain their offset; fixed coordinates
have no digits. Cap 1 is allowed, and a cap at least W gives the radix layout.

For levels 4, width 10 and cap 2, weights `[1,2,1]` with bounds `[3,3,1]`
have endpoint `3+6+1=10`. Nondivisible tails are explicit and can create duplicate
representations. Cap 1, levels 2 produces unary bits; cap 1 with larger levels
uses weight-one bounded integer digits. Duplicates change state multiplicities
and sampling neighborhoods. Exact polynomial substitution does not imply equal
sampling distributions or improved performance.

Levels 2 is an exact bounded-weight binary special case. Tests cross-check it
against an independently evaluated construction: take the powers-of-two prefix
while it fits the width/cap, then split the remaining width into repeated cap
weights and one residual weight. The qudit strategy and shared canonical lift
are tested separately from the reference; no vendor performance equivalence is
claimed.

Invalid Boolean/noninteger/nonpositive weight caps, level caps below 2, empty
integer intervals and nonfinite native bounds are rejected. Construction uses
BigInt arithmetic; compilation checks exact representability in its coefficient
type and rejects nonfinite transformed coefficients. `max_digits=256` limits
each coordinate before construction grows without bound. `MaxEncodedVariables()`
independently limits the full target. Both are configurable software guards.
Refused layouts report the width, caps, required digit count and configured limit
before allocating digits. Raise `max_digits`, `max_weight` or `levels` as appropriate.
Continuous variables are not discretized. Float64/BigFloat polynomial checks
retain the chosen arithmetic precision described in [the interface](encoding.md).

## Weight caps and final coefficients

The encoding cap constrains B's integer weights in `z=a+B*d`. It does **not**
constrain the final penalized quadratic or linear coefficients:

```math
G_d=B^TGB,\qquad g_d=B^T(g+(G+G^T)a).
```

Products of weights, original source coefficients, offsets and unchanged native
penalties can amplify these terms. A smaller cap can add variables and couplers.
Report actual coefficients and check a concrete provider manifest separately;
the weight cap does not certify device range, precision or embedding suitability.

Run the credential-free structural script from the repository environment:

```julia
include("benchmarks/bounded_structure.jl")
```

It compares a scalar quadratic `x^2+3x+5`, `x in -2:8`, and a model with two
bounded integers and four inequality slacks. Its independently chosen feasible
witness has energy 3 in every arm. The slack-heavy case uses the same native
penalty vector `[76,76,76,76]` in all arms. It records dimensions, active variables,
slack-owned auxiliaries, digit levels/weights, coupling structure and raw/canonical
coefficient ranges. It invokes no optimizer backend or hardware.

Raw G is the stored matrix in `z'G*z + g'z + c`: its diagonal is the square
coefficient and a unique off-diagonal coefficient is `G_ij+G_ji`. MOI quadratic
diagonal terms use twice `G_ii`. Raw entry maxima describe storage; compare
the unique canonical coefficients for polynomial coefficient ranges.

| Case / arm | Variables | Max weight | Max raw G | Max raw linear | Couplers | Canonical min/max abs |
|---|---:|---:|---:|---:|---:|---:|
| Scalar / native | 1 | 1 | 1 | 3 | 0 | 1 / 1 |
| Scalar / radix | 3 | 4 | 16 | 4 | 3 | 1 / 24 |
| Scalar / bounded | 3 | 2 | 4 | 2 | 3 | 1 / 4 |
| Slack-heavy / native | 6 | 1 | 534 | 1981 | 9 | 3 / 1981 |
| Slack-heavy / radix | 8 | 3 | 684 | 2736 | 15 | 3 / 2052 |
| Slack-heavy / bounded | 9 | 2 | 534 | 1981 | 19 | 3 / 1981 |

All encoded digits have at most 4 levels. Native maximum levels are 11 and 7
for these cases. Canonical coefficients shift active coordinates by their lower
endpoints, substitute fixed values into the constant, fold binary squares into
linear terms, and use unique off-diagonal coefficients `G_ij+G_ji`. Density is
`2*couplers/(N_active*(N_active-1))`, zero for fewer than two active variables.
The script also reports minimum nonzero magnitude, maximum magnitude and their
ratio. The scalar bounded example's ratio is 4 versus radix's 24; this is a
structural measurement on this model, not a solve-time or quality conclusion.

The artifact also records exact state counts and preimage multiplicities under
projection to the **full native state, including inequality slacks**. Independent
per-coordinate counting uses bounded dynamic programming, avoiding enumeration
of the full digit product. The native-state budget is 10,000.

| Case / arm | Target states | Native states | Min/max preimages |
|---|---:|---:|---:|
| Scalar / native | 11 | 11 | 1 / 1 |
| Scalar / radix | 16 | 11 | 1 / 2 |
| Scalar / bounded | 32 | 11 | 1 / 4 |
| Slack-heavy / native | 8064 | 8064 | 1 / 1 |
| Slack-heavy / radix | 12288 | 8064 | 1 / 4 |
| Slack-heavy / bounded | 24576 | 8064 | 1 / 8 |

These counts describe representations, not sampler quality or source-only
multiplicity after dropping slacks.

```@example bounded_structure
using ToQUIO
include(joinpath(pkgdir(ToQUIO), "benchmarks", "bounded_structure.jl"))
```

## Provenance and replay

[Karimi and Ronagh's primary preprint](https://arxiv.org/abs/1706.01945),
*Practical Integer-to-Binary Mapping for Quantum Annealers*, motivates bounded
coefficients in binary encoding. The inspected
[ToQUBO source](https://github.com/JuliaQUBO/ToQUBO.jl/blob/69ac52592f4c47ed2168bf480c9947d1fcbbfc2c/src/encoding/variables/interval/bounded.jl)
at revision `69ac52592f4c47ed2168bf480c9947d1fcbbfc2c` is MPL 2.0 (PSR, 2022).
Its pinned residual-map coverage findings are recorded in
[the study protocol](study.md). This implementation independently derives that
protocol's exact coverage construction and is covered by this repository's
existing MPL 2.0 license. The reference provides design context, not a claim of
reproducing its experiments or validating its implementation.

Use `lift_native_state` for the authoritative decreasing-weight, stable-tie
canonical lift. Save the complete metadata and actual ordered digit state for
replay; different valid preimages can produce different sampler trajectories.
Parameter sweeps must record both caps and the compiler/source revision. The
fixed campaign owns performance conclusions and tuning; hardware evidence has
its separate approval and admission gates.

```@docs
ToQUIO.BoundedEncoding
```
