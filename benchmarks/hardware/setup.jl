# Pass the source downloaded at the revision in qci_source_pin.json.
using Pkg
length(ARGS) == 1 || error("Pass the pinned QCIOpt source directory.")
Pkg.develop([PackageSpec(path = normpath(joinpath(@__DIR__, "../.."))),
             PackageSpec(path = abspath(only(ARGS)))])
Pkg.instantiate()
using JSON, SHA
pin = JSON.parsefile(joinpath(@__DIR__, "qci_source_pin.json"))
for (file, digest) in pin["files"]
    bytes2hex(sha256(read(joinpath(only(ARGS), file)))) == digest ||
        error("QCIOpt source does not match the pinned revision: $file")
end
using QCIOpt
println("Prepared pinned QCIOpt ", pin["revision"], " with its CondaPkg environment.")
