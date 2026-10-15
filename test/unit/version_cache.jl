@testset "Version-only change with reused compiled cache" begin
    mktempdir() do fixture
        cp(joinpath(pkgdir(ToQUIO), "src"), joinpath(fixture, "src"))
        project = joinpath(fixture, "Project.toml")
        text = read(joinpath(pkgdir(ToQUIO), "Project.toml"), String)
        current = string(pkgversion(ToQUIO))
        needle = "version = \"$current\""
        @test occursin(needle, text)
        write(project, replace(text, needle => "version = \"0.1.0\""; count = 1))
        # Preserve the actual lane's dependency resolution, including minimum MOI.
        cp(joinpath(dirname(Base.active_project()), "Manifest.toml"),
            joinpath(fixture, "Manifest.toml"))
        function probe(version)
            source_path = repr(joinpath(fixture, "src", "ToQUIO.jl"))
            code = "using ToQUIO; @assert pathof(ToQUIO)==$source_path; " *
                "@assert string(pkgversion(ToQUIO))==$(repr(version)); " *
                "@assert ToQUIO.MOI.get(ToQUIO.Optimizer(),ToQUIO.MOI.SolverVersion())==$(repr(version))"
            command = `$(Base.julia_cmd()) --startup-file=no --project=$fixture -e $code`
            limiter = Sys.which("timeout")
            return success(isnothing(limiter) ? command : `$limiter 120 $command`)
        end
        @test probe("0.1.0")
        # No cache/depot deletion or source change: alter only version metadata.
        write(project, text)
        @test probe(current)
    end
end
