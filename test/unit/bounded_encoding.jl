# Independent binary construction: grow a powers-of-two prefix, then split the
# residual by quotient/remainder at the cap. It does not call either encoder.
function bounded_binary_reference(width, cap)
    weights = BigInt[]
    power, covered = big(1), big(0)
    while power <= cap && covered + power <= width
        push!(weights, power)
        covered += power
        power *= 2
    end
    repetitions, remainder = divrem(big(width) - covered, big(cap))
    length(weights) + repetitions + (remainder > 0) <= 256 ||
        throw(ArgumentError("Binary reference allocation exceeds its budget."))
    append!(weights, fill(big(cap), Int(repetitions)))
    iszero(remainder) || push!(weights, remainder)
    return weights
end

@testset "Exact bounded-weight integer encoding" begin
    @testset "caps, parameters and refusals" begin
        for cap in (false, 0, -1, 1.0, Inf, NaN)
            @test_throws ArgumentError ToQUIO.BoundedEncoding(; max_weight = cap)
        end
        for levels in (false, 0, 1, 2.5, Inf)
            @test_throws ArgumentError ToQUIO.BoundedEncoding(; levels)
        end
        for digits in (false, 0, -1, 1.5)
            @test_throws ArgumentError ToQUIO.BoundedEncoding(; max_digits = digits)
        end
        encoding = ToQUIO.BoundedEncoding()
        @test (encoding.levels, encoding.max_weight, encoding.max_digits) == (4, 2, 256)
        @test ToQUIO.encoding_descriptor(encoding) == Dict(
            "name" => "bounded", "construction" => "exact-bounded-tail-v1",
            "levels" => 4, "max_weight" => 2, "max_digits" => 256)
        @test_throws ArgumentError ToQUIO.variable_encoding(encoding, 2, 1; context = nothing)
        @test_throws ArgumentError ToQUIO.variable_encoding(
            ToQUIO.BoundedEncoding(; levels = 2, max_weight = 1, max_digits = 3),
            -2, 8; context = nothing)
        large_cap = ToQUIO.BoundedEncoding(; max_weight = big(2)^100)
        @test large_cap.max_weight isa BigInt
        @test ToQUIO.variable_encoding(large_cap, -2, 8; context = nothing).weights == [1, 4, 3]
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 2.0^56)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        @test_throws ArgumentError RMOI.optimize!(ToQUIO.Optimizer(;
            encoding = ToQUIO.BoundedEncoding(; max_weight = big(2)^56, levels = big(2)^56)), source)
        @test_throws ArgumentError RMOI.optimize!(ToQUIO.Optimizer(;
            encoding = ToQUIO.BoundedEncoding(; levels = 2, max_weight = 1, max_digits = 4)), source)
        @test RMOI.get(ToQUIO.Optimizer(), ToQUIO.EncodingStrategy()) isa ToQUIO.NativeEncoding
    end

    @testset "actionable refusals without constructing oversized layouts" begin
        error = try
            ToQUIO.variable_encoding(
                ToQUIO.BoundedEncoding(; levels = 2, max_weight = 1, max_digits = 3),
                -2, 8; context = nothing)
        catch exception
            exception
        end
        @test error isa ArgumentError
        message = sprint(showerror, error)
        for fragment in ("Bounded", "width=10", "levels=2", "max_weight=1",
                         "requires 10 digits", "max_digits=3", "Increase")
            @test occursin(fragment, message)
        end
        @test_throws ArgumentError ToQUIO.variable_encoding(
            ToQUIO.BoundedEncoding(; levels = 2, max_weight = 1),
            0, big(10)^100; context = nothing)
        for width in 0:100, levels in 2:8, cap in (nothing, 1, 2, 3, 5, 7, 16)
            strategy = isnothing(cap) ? ToQUIO.RadixEncoding(; levels) :
                       ToQUIO.BoundedEncoding(; levels, max_weight = cap)
            layout = ToQUIO.variable_encoding(strategy, 0, width; context = nothing)
            @test ToQUIO._bounded_tail_digit_count(width, levels, cap) == length(layout.weights)
        end
    end

    @testset "complete tiny digit images and independent binary limit" begin
        for lower in (-7, 0, 5), width in 0:12, levels in 2:5, cap in (1, 2, 3, 4, 5, 6, 7, 20)
            strategy = ToQUIO.BoundedEncoding(; levels, max_weight = cap)
            layout = ToQUIO.variable_encoding(strategy, lower, lower + width; context = nothing)
            @test all(1 .<= layout.weights .<= cap)
            @test all(1 .<= layout.upper_bounds .< levels)
            @test layout.offset == lower
            @test sum(big.(layout.weights) .* layout.upper_bounds; init = big(0)) == width
            count = prod(big(m) + 1 for m in layout.upper_bounds; init = big(1))
            count <= 10_000 || throw(ArgumentError("Bounded test enumeration exceeds its budget."))
            images = Set{BigInt}()
            for digits in Iterators.product((0:m for m in layout.upper_bounds)...)
                point = big(lower) + sum(big(w)*d for (w, d) in zip(layout.weights, digits); init = big(0))
                @test lower <= point <= lower + width
                @test ToQUIO._decode_layout(layout, collect(digits)) == point
                push!(images, point)
            end
            @test images == Set(big(lower):big(lower + width))
            for point in lower:(lower + width)
                lifted = ToQUIO._canonical_digits(layout, point)
                @test all(0 .<= lifted .<= layout.upper_bounds)
                @test lower + sum(big(w)*d for (w, d) in zip(layout.weights, lifted); init = big(0)) == point
            end
            if levels == 2
                @test layout.weights == bounded_binary_reference(width, cap)
                @test all(isone, layout.upper_bounds)
            end
            if cap >= width
                radix = ToQUIO.variable_encoding(ToQUIO.RadixEncoding(; levels), lower, lower + width;
                                                context = nothing)
                @test (layout.weights, layout.upper_bounds) == (radix.weights, radix.upper_bounds)
            end
        end
    end

    @testset "wider exact images by independent reachable-sum DP" begin
        for width in 0:32, levels in 2:5, cap in (1, 2, 3, 4, 5, 6, 7)
            layout = ToQUIO.variable_encoding(ToQUIO.BoundedEncoding(; levels, max_weight = cap),
                                             -9, width - 9; context = nothing)
            image = Set([big(-9)])
            for (w, m) in zip(layout.weights, layout.upper_bounds)
                image = Set(p + w*d for p in image for d in 0:m)
            end
            @test image == Set(big(-9):big(width - 9))
            @test all(layout.weights .<= cap)
        end
    end

    @testset "wider independent binary reference and nonbinding weight cap" begin
        for width in 0:40, cap in (1, 2, 3, 4, 5, 6, 7)
            layout = ToQUIO.variable_encoding(ToQUIO.BoundedEncoding(; levels = 2, max_weight = cap),
                                             0, width; context = nothing)
            @test layout.weights == bounded_binary_reference(width, cap)
            @test sum(layout.weights .* layout.upper_bounds; init = big(0)) == width
        end
        # Width 14 needs weights at most 4 in radix4; cap4 is below the width.
        bounded = ToQUIO.variable_encoding(ToQUIO.BoundedEncoding(; max_weight = 4), -7, 7;
                                           context = nothing)
        radix = ToQUIO.variable_encoding(ToQUIO.RadixEncoding(), -7, 7; context = nothing)
        @test (bounded.weights, bounded.upper_bounds) == (radix.weights, radix.upper_bounds)
    end

    @testset "independent compiled energy and source feasibility" begin
        for sense in (RMOI.MIN_SENSE, RMOI.MAX_SENSE), levels in (2, 4), cap in (1, 2, 4)
            source, x, y, fixed, _, _ = encoding_fixture(sense)
            ci = RMOI.ConstraintIndex{RMOI.VariableIndex,RMOI.Interval{Float64}}(x.value)
            RMOI.set(source, RMOI.ConstraintSet(), ci, RMOI.Interval(-2.0, 2.0))
            native = ToQUIO.Optimizer()
            RMOI.optimize!(native, source)
            optimizer = ToQUIO.Optimizer(; encoding = ToQUIO.BoundedEncoding(; levels, max_weight = cap))
            RMOI.optimize!(optimizer, source)
            data = optimizer.data
            saved = ToQUIO.reformulation_metadata(data)
            @test data[:rho] == native.data[:rho]
            @test saved["native_reformulation"] == ToQUIO.reformulation_metadata(native)
            @test saved["encoding"]["strategy"]["max_weight"] == cap
            @test all(w <= cap for layout in data[:encoding_layouts] for w in layout.weights)
            @test all(data[:encoded_u] .< levels)
            @test [e["role"] for e in saved["native_variables"]] ==
                  ["original", "original", "original", "slack", "slack"]
            descriptor = saved["encoding"]["strategy"]
            replay = ToQUIO.BoundedEncoding(; levels = descriptor["levels"],
                max_weight = descriptor["max_weight"], max_digits = descriptor["max_digits"])
            @test ToQUIO.encoding_descriptor(replay) == descriptor
            native_saved = saved["native_reformulation"]
            next_position = 1
            for (i, entry) in enumerate(saved["native_variables"])
                layout = ToQUIO.variable_encoding(replay,
                    ceil(BigInt, native_saved["target_lower_bounds"][i]),
                    floor(BigInt, native_saved["target_upper_bounds"][i]); context = nothing)
                expansion = entry["expansion"]
                positions = [term["target_position"] for term in expansion["terms"]]
                @test expansion["offset"] == layout.offset
                @test [term["coefficient"] for term in expansion["terms"]] == layout.weights
                @test saved["target_upper_bounds"][positions] == layout.upper_bounds
                @test positions == collect(next_position:(next_position + length(positions) - 1))
                next_position += length(positions)
            end
            @test next_position == length(saved["target_variable_order"]) + 1
            count = prod(BigInt(m) + 1 for m in data[:encoded_u]; init = big(1))
            count <= 10_000 || throw(ArgumentError("Bounded compiled enumeration exceeds its budget."))
            sign = sense == RMOI.MIN_SENSE ? 1 : -1
            images = Set{Tuple}()
            for digits in Iterators.product((0:Int(m) for m in data[:encoded_u])...)
                d = collect(digits)
                z = [Int(layout.offset + sum(big(w)*d[p] for (w, p) in zip(layout.weights, positions);
                                            init = big(0)))
                     for (layout, positions) in zip(data[:encoding_layouts], data[:encoding_digit_positions])]
                push!(images, Tuple(z))
                original = 2z[1]^2 + 3z[1]*z[2] + z[2]^2 + 10z[1] - 4z[2] + 7
                expected = original + sign * (data[:rho][1]*(z[1] - z[2] + z[4])^2 +
                                             data[:rho][2]*(-z[1] - z[2] + z[5])^2)
                @test encoded_value(optimizer.target_model, data, d) == expected
                @test ToQUIO.project_original_state(data, d) == Dict(x => z[1], y => z[2], fixed => 2)
                @test ToQUIO.project_native_state(saved, d) == z
                @test ToQUIO.is_feasible(optimizer, d) == (z[1] <= z[2] && z[1] + z[2] >= 0)
                @test ToQUIO.project_native_state(data, ToQUIO.lift_native_state(data, z)) == z
            end
            @test images == Set(Tuple(z) for z in Iterators.product(-2:2, 0:1, 2:2, 0:3, 0:3))
        end
    end

    @testset "Float64 and BigFloat polynomial contract" begin
        for T in (Float64, BigFloat)
            source = RMOI.Utilities.Model{T}()
            x, y = RMOI.add_variables(source, 2)
            RMOI.add_constraint(source, x, RMOI.Interval(T(-2), T(3)))
            RMOI.add_constraint(source, x, RMOI.Integer())
            RMOI.add_constraint(source, y, RMOI.ZeroOne())
            f = RMOI.ScalarQuadraticFunction([
                RMOI.ScalarQuadraticTerm(T(2.5), x, x), RMOI.ScalarQuadraticTerm(T(0.75), x, y),
            ], [RMOI.ScalarAffineTerm(T(2), y)], T(3))
            RMOI.set(source, RMOI.ObjectiveFunction{typeof(f)}(), f)
            RMOI.set(source, RMOI.ObjectiveSense(), RMOI.MIN_SENSE)
            row = RMOI.ScalarAffineFunction([RMOI.ScalarAffineTerm(one(T), x),
                                             RMOI.ScalarAffineTerm(one(T), y)], zero(T))
            RMOI.add_constraint(source, row, RMOI.LessThan(one(T)))
            optimizer = ToQUIO.Optimizer{T}(; encoding = ToQUIO.BoundedEncoding())
            RMOI.optimize!(optimizer, source)
            @test eltype(optimizer.data[:encoded_Q]) == T
            @test optimizer.data[:encoded_u] == [3, 1, 1, 3]
            for digits in Iterators.product(0:3, 0:1, 0:1, 0:3)
                d = collect(digits)
                xv, yv, slack = -2 + d[1] + 2d[2], d[3], d[4]
                expected = T(1.25)*xv^2 + T(0.75)*xv*yv + 2yv + 3 +
                           only(optimizer.data[:rho])*(xv + yv + slack - 1)^2
                @test encoded_value(optimizer.target_model, optimizer.data, d) == expected
            end
        end
    end

    @testset "recorded scalar and slack-heavy structure" begin
        proof = Module(:BoundedStructureProof)
        rows = Base.include(proof, joinpath(pkgdir(ToQUIO), "benchmarks", "bounded_structure.jl"))
        @test [r.variables for r in rows] == [1, 3, 3, 6, 8, 9]
        @test [r.auxiliaries for r in rows] == [0, 0, 0, 4, 6, 7]
        @test [r.max_levels for r in rows] == [11, 4, 4, 7, 4, 4]
        @test [r.max_weight for r in rows] == [1, 4, 2, 1, 3, 2]
        @test [r.couplers for r in rows] == [0, 3, 3, 9, 15, 19]
        @test [r.raw_Q_max for r in rows] == [1, 16, 4, 534, 684, 534]
        @test [r.raw_L_max for r in rows] == [3, 4, 2, 1981, 2736, 1981]
        @test [r.coefficient_max for r in rows] == [1, 24, 4, 1981, 2052, 1981]
        @test [r.nonbinary_squares for r in rows] == [1, 1, 2, 6, 6, 6]
        @test [r.target_states for r in rows] == [11, 16, 32, 8064, 12288, 24576]
        @test [r.native_states for r in rows] == [11, 11, 11, 8064, 8064, 8064]
        @test [r.preimages_min for r in rows] == ones(Int, 6)
        @test [r.preimages_max for r in rows] == [1, 2, 4, 1, 4, 8]
        @test all(r.energy == 3 for r in rows)
        @test all(r.rho == [76, 76, 76, 76] for r in rows[4:6])
        @test rows[3].coefficient_max > rows[3].weight_cap
        @test rows[6].variables > rows[5].variables
        @test rows[6].coefficient_max > rows[6].weight_cap
        example = Base.invokelatest(getproperty, proof, :BoundedStructureExample)
        make_source = Base.invokelatest(getproperty, example, :structural_source)
        canonicalize = Base.invokelatest(getproperty, example, :canonical_polynomial)
        multiplicities = Base.invokelatest(getproperty, example, :multiplicity_statistics)
        for (strategy, weights) in ((ToQUIO.NativeEncoding(), Int[]),
                                    (ToQUIO.RadixEncoding(), [1, 4, 3]),
                                    (ToQUIO.BoundedEncoding(), [1, 2, 1]))
            source, _, _, _ = Base.invokelatest(make_source, "scalar")
            optimizer = ToQUIO.Optimizer(; encoding = strategy)
            RMOI.optimize!(optimizer, source)
            canonical = Base.invokelatest(canonicalize, optimizer)
            @test_throws ArgumentError Base.invokelatest(multiplicities, optimizer; max_native_states = 1)
            data = optimizer.data
            lower = haskey(data, :encoded_l) ? data[:encoded_l] : data[:l]
            upper = haskey(data, :encoded_u) ? data[:encoded_u] : data[:u]
            preimages = Dict{Int,Int}()
            for state in Iterators.product((Int(l):Int(u) for (l, u) in zip(lower, upper))...)
                digits = collect(state)
                x = isempty(weights) ? only(digits) : -2 + sum(weights .* digits)
                preimages[x] = get(preimages, x, 0) + 1
                expected = x^2 + 3x + 5
                shifted = (digits - canonical.offset)[canonical.active]
                @test encoded_value(optimizer.target_model, data, digits) == expected
                @test ToQUIO.LinearAlgebra.dot(shifted, canonical.G * shifted) +
                      ToQUIO.LinearAlgebra.dot(canonical.g, shifted) + canonical.constant == expected
            end
            measured = Base.invokelatest(multiplicities, optimizer)
            @test measured.target_states == sum(values(preimages))
            @test measured.preimages_min == minimum(values(preimages))
            @test measured.preimages_max == maximum(values(preimages))
        end
    end
end
