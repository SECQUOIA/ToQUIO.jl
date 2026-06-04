const MOI = ToQUIO.MOI

function scalar_affine(terms::Vector{Tuple{Float64,MOI.VariableIndex}}, constant::Float64)
    return MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(first.(terms), last.(terms)), constant)
end

@testset "GreaterThan reformulation regression" begin
    model = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    x = MOI.add_variable(model)

    MOI.add_constraint(model, x, MOI.Interval(0.0, 10.0))

    f = scalar_affine([(2.0, x)], 1.0)
    MOI.add_constraint(model, f, MOI.GreaterThan(5.0))

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

    A_gt, b_gt = ToQUIO.get_gt_matrices(Float64, vi -> vi.value, ci -> ci.value, model)
    @test A_gt == [2.0;;]
    @test b_gt == [4.0]

    _, data = ToQUIO.to_quio(Float64, vi -> vi.value, ci -> ci.value, model)
    @test data[:n] == 2
end

@testset "ZeroOne bounds regression" begin
    model = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    x = MOI.add_variable(model)

    MOI.add_constraint(model, x, MOI.ZeroOne())

    f = scalar_affine([(1.0, x)], 0.0)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

    _, data = ToQUIO.to_quio(Float64, vi -> vi.value, ci -> ci.value, model)
    @test data[:l][1] == 0.0
    @test data[:u][1] == 1.0
end
