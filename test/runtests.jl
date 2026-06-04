using Test
using ToQUIO

@testset "ToQUIO" begin
    include("unit/maintenance.jl")
    include("unit/to_quio_regression.jl")
end
