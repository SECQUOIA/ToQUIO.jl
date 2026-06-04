using Test

const DOC_ROOT = normpath(joinpath(@__DIR__, ".."))

function extract_julia_blocks(path::AbstractString)
    blocks = Tuple{Int,String}[]
    lines = readlines(path)
    in_block = false
    start_line = 0
    block = String[]

    for (line_number, line) in pairs(lines)
        stripped = strip(line)
        if !in_block && startswith(stripped, "```julia")
            in_block = true
            start_line = line_number + 1
            empty!(block)
        elseif in_block && startswith(stripped, "```")
            push!(blocks, (start_line, join(block, "\n")))
            in_block = false
        elseif in_block
            push!(block, line)
        end
    end

    return blocks
end

function should_run_doc_block(code::AbstractString)
    contains(code, "optimize!(model)") || return false
    contains(code, "QUBOSolver") && return false
    contains(code, "SomeQUIOSolver") && return false
    return true
end

function run_doc_block(path::AbstractString, line::Integer, code::AbstractString)
    module_name = Symbol("DocExample_", replace(relpath(path, DOC_ROOT), r"[^A-Za-z0-9]" => "_"), "_", line)
    mod = Module(module_name)
    include_string(mod, code, "$(relpath(path, DOC_ROOT)):$line")
    return nothing
end

@testset "Documentation Examples" begin
    docs = [
        joinpath(DOC_ROOT, "README.md"),
        joinpath(DOC_ROOT, "docs", "examples.md"),
    ]

    runnable_blocks = Tuple{String,Int,String}[]
    for path in docs
        for (line, code) in extract_julia_blocks(path)
            should_run_doc_block(code) || continue
            push!(runnable_blocks, (path, line, code))
        end
    end

    @test !isempty(runnable_blocks)

    for (path, line, code) in runnable_blocks
        @testset "$(relpath(path, DOC_ROOT)):$line" begin
            run_doc_block(path, line, code)
            @test true
        end
    end
end
