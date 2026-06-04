const MOI = ToQUIO.MOI

@testset "Reformulation data extraction" begin
    @testset "Supported bound constraints" begin
        optimizer = ToQUIO.Optimizer()

        @test MOI.supports_constraint(
            optimizer,
            MOI.VariableIndex,
            MOI.GreaterThan{Float64},
        )
        @test MOI.supports_constraint(
            optimizer,
            MOI.VariableIndex,
            MOI.LessThan{Float64},
        )
        @test MOI.supports_constraint(
            optimizer,
            MOI.VariableIndex,
            MOI.Interval{Float64},
        )
    end

    @testset "ZeroOne variable bounds" begin
        source = MOI.Utilities.Model{Float64}()
        x = MOI.add_variable(source)
        MOI.add_constraint(source, x, MOI.ZeroOne())

        l, u = ToQUIO.get_variable_bounds(Float64, vi -> vi.value, source)

        @test l == [0.0]
        @test u == [1.0]
    end

    @testset "GreaterThan affine matrix" begin
        source = MOI.Utilities.Model{Float64}()
        x = MOI.add_variable(source)
        f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(2.0, x)], 3.0)
        MOI.add_constraint(source, f, MOI.GreaterThan(7.0))

        A, b = ToQUIO.get_gt_matrices(Float64, vi -> vi.value, ci -> ci.value, source)

        @test A == reshape([2.0], 1, 1)
        @test b == [4.0]
    end
end
