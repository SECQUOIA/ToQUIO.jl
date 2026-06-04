using TOML

@testset "Root compat policy" begin
    project = TOML.parsefile(joinpath(pkgdir(ToQUIO), "Project.toml"))
    compat = project["compat"]

    @test compat["julia"] == "1.10"
    @test compat["LinearAlgebra"] == "1"
    @test compat["MathOptInterface"] == "1"
end
