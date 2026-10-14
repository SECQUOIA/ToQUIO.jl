using Pkg
Pkg.develop(PackageSpec(path = normpath(joinpath(@__DIR__, "../.."))))
Pkg.instantiate()
