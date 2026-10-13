# Bounded-domain radix encoding

`RadixEncoding(; levels=4)` limits each digit to at most four integer values.
It applies the [encoding interface](encoding.md) to originals and generated
slacks, retaining the source penalties and composed decoding. Strategy parameters
and actual digit bounds/weights/offsets are recorded in schema version 2 metadata.
The default optimizer still uses `NativeEncoding()`.

For native integer endpoints `L=ceil(l)` and `U=floor(u)`, set `W=U-L`.
Start at covered endpoint `C=0`. While `C<W`, append

```math
w=\min(C+1,W-C),\qquad m=\min(\mathrm{levels}-1,\lfloor(W-C)/w\rfloor),
\qquad C\leftarrow C+wm.
```

The coordinate is `L+sum(w_j*d_j)`, with integer digits `0<=d_j<=m_j`.
If previous digits cover every integer `0:C`, the translated intervals for the
new digit touch or overlap because `w<=C+1`. Their union is `0:C+w*m`.
Since `w<=W-C` and `levels-1>=1`, the new digit bound `m>=1`.
Each step increases coverage and stays within W; eventually the endpoint is
exactly W. Thus every source integer has a representation and every allowed
digit assignment stays in the source interval, with no enforcement penalty.

Fixed coordinates have no digit. When `W<levels`, the construction uses one
weight-one digit, retaining the original number of levels and a lower offset L.
This is identity in domain size; the digits still have zero lower bounds and
fixed coordinates are removed. Global `NativeEncoding()` is the unchanged native
model when preserving its literal coordinates is desired.

Full radix powers are used where they fit; a bounded final tail completes other
widths. For levels 4, width 14 has weights `[1,4,3]` and upper bounds `[3,2,1]`:
the endpoint is `3+8+3=14`. Tails can overlap previous representations. Width 4
has weights `[1,1]`, bounds `[3,1]`: values 1, 2 and 3 each have two representations,
while endpoints 0 and 4 each have one. These
duplicates affect multiplicity and sampling neighborhoods. The strategy does not
promise the minimum digit count or a faster solve.

Levels 2 gives the bounded-tail binary special case: width 6 has weights
`[1,2,3]` and bounds `[1,1,1]`. This mathematical reduction is not performance
equivalence with a separately implemented binary compiler.

`lift_native_state` is the authoritative canonical lift for controlled
initialization and replay. It chooses decreasing weights, with ties in original
digit order. The protocol helper follows this order, including unsorted tails:
levels 4, width 14, value 5 lifts to `[1,1,0]` for weights `[1,4,3]`.

The levels cap must be an integer at least 2; Booleans and floating caps are
rejected. Layout arithmetic uses BigInt, and compilation rejects integers not
exactly representable in its coefficient type. Native source variables must
already be Integer/ZeroOne with finite bounds and a nonempty integer interval;
continuous variables are not discretized. Floating polynomial arithmetic retains
its chosen precision. `max_digits=256` guards each coordinate's construction;
`MaxEncodedVariables()` independently guards the full target allocation. Both
limits are configurable and neither is a hardware capability claim.

## Credential-free JuMP example

Install JuMP separately in your chosen example environment, as in the README.
Run `docs/examples/radix_encoding.jl`; it uses reformulation-only optimizers and
requires no solver, service credentials or device. The script builds this model
for native, levels-4 and levels-2 strategies:

```julia
using JuMP, ToQUIO
optimizer = ToQUIO.Optimizer(; encoding=RadixEncoding(; levels=4))
model = Model(() -> optimizer)
@variable(model, -2 <= x <= 5, Int)
@variable(model, y, Bin)
@variable(model, fixed == 2, Int)
@constraint(model, x + y <= 3)
@objective(model, Max, 3x + 2y + fixed)
optimize!(model)
digits = lift_native_state(optimizer, [1, 1, 2, 1])
@assert project_native_state(optimizer, digits) == [1, 1, 2, 1]
@assert is_feasible(optimizer, digits)
```

The full script independently checks energy 7 and unchanged penalties for that
feasible state, and reports actual target variable counts and digit levels.
It compares structure and polynomial equality, without measuring performance.

| Arm | Target variables | Maximum target levels | Checked energy |
|---|---:|---:|---:|
| Native | 4 | 8 | 7 |
| Radix, levels 4 | 5 | 4 | 7 |
| Radix, levels 2 | 7 | 2 | 7 |

The native count includes the fixed coordinate; the encoded models restore it
from a constant expansion. These counts describe this model only.

Unit tests exhaust every tiny domain, verify full image coverage and canonical
lifts, and enumerate every target global optimum for mixed quadratic fixtures
under both objective senses and sufficient native penalties.

```@docs
ToQUIO.RadixEncoding
```
