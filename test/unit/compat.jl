using TOML

const TEST_PROJECT_DEPS = Dict(
    "Test" => "8dfed614-e22c-5e08-85e1-65c5234f0b40",
    "TOML" => "fa267f1f-6049-4f14-aa54-33bafae1ed76",
    "ToQUIO" => "c8c7c8a1-01ab-43fa-b80d-8804f80d4aae",
)

function normalized_dependabot_directory(value::AbstractString)
    value = strip(value)
    if endswith(value, ",")
        value = strip(value[begin:prevind(value, end)])
    end
    if (startswith(value, "\"") && endswith(value, "\"")) ||
       (startswith(value, "'") && endswith(value, "'"))
        value = value[2:(end - 1)]
    end
    return value
end

is_test_directory(value::AbstractString) = normalized_dependabot_directory(value) in ("/test", "/test/")

function inline_yaml_values(value::AbstractString)
    value = strip(value)
    if startswith(value, "[") && endswith(value, "]")
        value = value[2:(end - 1)]
    end
    return split(value, ",")
end

# Dependabot config is YAML, but this guard only needs to detect exact Julia
# entries for /test without accepting paths like /testing.
function has_julia_test_dependabot_entry(config::AbstractString)
    in_julia_update = false
    in_multiline_directories = false

    for raw_line in split(config, '\n')
        line = strip(raw_line)
        isempty(line) && continue

        ecosystem = match(r"""^-?\s*package-ecosystem:\s*(.+?)\s*$""", line)
        if ecosystem !== nothing
            in_julia_update = normalized_dependabot_directory(ecosystem.captures[1]) == "julia"
            in_multiline_directories = false
            continue
        end

        in_julia_update || continue

        directory = match(r"""^directory:\s*(.+?)\s*$""", line)
        if directory !== nothing
            in_multiline_directories = false
            is_test_directory(directory.captures[1]) && return true
            continue
        end

        directories = match(r"""^directories:\s*(.*?)\s*$""", line)
        if directories !== nothing
            value = strip(directories.captures[1])
            in_multiline_directories = isempty(value)
            any(is_test_directory, inline_yaml_values(value)) && return true
            continue
        end

        if in_multiline_directories
            item = match(r"""^-\s*(.+?)\s*$""", line)
            if item !== nothing
                is_test_directory(item.captures[1]) && return true
            else
                in_multiline_directories = false
            end
        end
    end

    return false
end

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
        @test !has_julia_test_dependabot_entry(read(dependabot_config, String))
    else
        # Dormant until a Dependabot config is added; the policy is enforced
        # above by requiring no test-specific compat bounds.
    end
end

@testset "Dependabot /test entry detection" begin
    @test has_julia_test_dependabot_entry("""
        updates:
          - package-ecosystem: "julia"
            directory: "/test"
    """)
    @test has_julia_test_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directory: /test/
    """)
    @test has_julia_test_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directories: ["/", "/test"]
    """)
    @test has_julia_test_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directories:
              - "/"
              - "/test"
    """)

    @test !has_julia_test_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directory: /testing
    """)
    @test !has_julia_test_dependabot_entry("""
        updates:
          - package-ecosystem: github-actions
            directory: "/test"
    """)
end
