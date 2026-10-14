using Test, ToQUIO
@assert realpath(pkgdir(ToQUIO)) == realpath(joinpath(@__DIR__, "../.."))
include("radix_encoding.jl")
include("encoding_choices.jl")
include("tiny_replay.jl")

@testset "Public examples and portable smoke replay" begin
    @test length(radix_structural_comparison()) == 3
    @test length(EncodingChoicesExample.RESULTS) == 4
    mktempdir() do parent
        root = joinpath(parent, "tiny")
        TinyReplayExample.create(root)
        @test TinyReplayExample.replay(root)
        @test_throws ErrorException TinyReplayExample.create(root)
        open(joinpath(root, "trajectory.toml"), "a") do io
            write(io, "\n# corrupted retained record\n")
        end
        @test_throws ErrorException TinyReplayExample.replay(root)
    end
end
