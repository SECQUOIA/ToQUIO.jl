using TOML

const TEST_PROJECT_DEPS = Dict(
    "Test" => "8dfed614-e22c-5e08-85e1-65c5234f0b40",
    "TOML" => "fa267f1f-6049-4f14-aa54-33bafae1ed76",
    "ToQUIO" => "c8c7c8a1-01ab-43fa-b80d-8804f80d4aae",
)

@testset "Root compat policy" begin
    project = TOML.parsefile(joinpath(pkgdir(ToQUIO), "Project.toml"))
    compat = project["compat"]

    @test compat["julia"] == "1.10"
    @test compat["LinearAlgebra"] == "1"
    @test compat["MathOptInterface"] == "1"
end

@testset "Test environment compat policy" begin
    project = TOML.parsefile(joinpath(pkgdir(ToQUIO), "test", "Project.toml"))

    @test project["deps"] == TEST_PROJECT_DEPS
    @test !haskey(project, "compat")

    dependabot_config = joinpath(pkgdir(ToQUIO), ".github", "dependabot.yml")
    if isfile(dependabot_config)
        @test !occursin(r"""directory:\s*["']?/test["']?""", read(dependabot_config, String))
    else
        @test true
    end
end
