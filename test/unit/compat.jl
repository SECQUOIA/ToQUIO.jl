using TOML

const TEST_PROJECT_DEPS = Dict(
    "Test" => "8dfed614-e22c-5e08-85e1-65c5234f0b40",
    "TOML" => "fa267f1f-6049-4f14-aa54-33bafae1ed76",
    "ToQUIO" => "c8c7c8a1-01ab-43fa-b80d-8804f80d4aae",
)

const SUPPORTED_JULIA_VERSIONS = ("1.10", "1")

function normalized_yaml_scalar(value::AbstractString)
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

function has_yaml_sequence_value(config::AbstractString, value::AbstractString)
    for raw_line in split(config, '\n')
        line = strip(raw_line)
        item = match(r"""^-\s*(.+?)\s*$""", line)
        item === nothing && continue
        normalized_yaml_scalar(item.captures[1]) == value && return true
    end

    return false
end

function normalized_dependabot_directory(value::AbstractString)
    directory = normalized_yaml_scalar(value)
    directory == "/" && return directory
    return rstrip(directory, '/')
end

is_dependabot_directory(value::AbstractString, directory::AbstractString) =
    normalized_dependabot_directory(value) == normalized_dependabot_directory(directory)

function inline_yaml_values(value::AbstractString)
    value = strip(value)
    if startswith(value, "[") && endswith(value, "]")
        value = value[2:(end - 1)]
    end
    return split(value, ",")
end

# Dependabot config is YAML, but these guards only need to detect exact
# ecosystem/directory entries without accepting paths like /testing.
function has_dependabot_entry(
    config::AbstractString;
    ecosystem::AbstractString,
    directory::AbstractString,
)
    in_matching_update = false
    in_multiline_directories = false

    for raw_line in split(config, '\n')
        line = strip(raw_line)
        isempty(line) && continue

        ecosystem_match = match(r"""^-?\s*package-ecosystem:\s*(.+?)\s*$""", line)
        if ecosystem_match !== nothing
            in_matching_update = normalized_yaml_scalar(ecosystem_match.captures[1]) == ecosystem
            in_multiline_directories = false
            continue
        end

        in_matching_update || continue

        directory_match = match(r"""^directory:\s*(.+?)\s*$""", line)
        if directory_match !== nothing
            in_multiline_directories = false
            is_dependabot_directory(directory_match.captures[1], directory) && return true
            continue
        end

        directories_match = match(r"""^directories:\s*(.*?)\s*$""", line)
        if directories_match !== nothing
            value = strip(directories_match.captures[1])
            in_multiline_directories = isempty(value)
            any(value -> is_dependabot_directory(value, directory), inline_yaml_values(value)) &&
                return true
            continue
        end

        if in_multiline_directories
            item = match(r"""^-\s*(.+?)\s*$""", line)
            if item !== nothing
                is_dependabot_directory(item.captures[1], directory) && return true
            else
                in_multiline_directories = false
            end
        end
    end

    return false
end

has_julia_dependabot_entry(config::AbstractString, directory::AbstractString) =
    has_dependabot_entry(config; ecosystem = "julia", directory = directory)

has_github_actions_dependabot_entry(config::AbstractString) =
    has_dependabot_entry(config; ecosystem = "github-actions", directory = "/")

@testset "Root compat policy" begin
    project = TOML.parsefile(joinpath(pkgdir(ToQUIO), "Project.toml"))
    compat = project["compat"]

    @test compat["julia"] == first(SUPPORTED_JULIA_VERSIONS)
    @test compat["LinearAlgebra"] == "1"
    @test compat["MathOptInterface"] == "1"
end

@testset "CI workflow policy" begin
    ci_workflow = joinpath(pkgdir(ToQUIO), ".github", "workflows", "ci.yml")
    @test isfile(ci_workflow)

    ci_config = read(ci_workflow, String)
    @test occursin(r"(?m)^\s*pull_request\s*:", ci_config)
    @test occursin("julia-actions/setup-julia", ci_config)
    @test occursin("julia-actions/julia-runtest", ci_config)
    @test all(version -> has_yaml_sequence_value(ci_config, version), SUPPORTED_JULIA_VERSIONS)
end

@testset "Test environment compat policy" begin
    project = TOML.parsefile(joinpath(pkgdir(ToQUIO), "test", "Project.toml"))

    @test project["deps"] == TEST_PROJECT_DEPS
    @test !haskey(project, "compat")

    dependabot_config = joinpath(pkgdir(ToQUIO), ".github", "dependabot.yml")
    if isfile(dependabot_config)
        @test !has_julia_dependabot_entry(read(dependabot_config, String), "/test")
    else
        # Dormant until a Dependabot config is added; the policy is enforced
        # above by requiring no test-specific compat bounds.
    end
end

@testset "Dependabot config policy" begin
    dependabot_config = joinpath(pkgdir(ToQUIO), ".github", "dependabot.yml")
    if isfile(dependabot_config)
        config = read(dependabot_config, String)

        @test has_julia_dependabot_entry(config, "/")
        @test has_github_actions_dependabot_entry(config)
    else
        # Dormant until a Dependabot config is added.
    end
end

@testset "Dependabot entry detection" begin
    @test has_julia_dependabot_entry("""
        updates:
          - package-ecosystem: "julia"
            directory: "/"
    """, "/")
    @test has_github_actions_dependabot_entry("""
        updates:
          - package-ecosystem: github-actions
            directory: "/"
    """)
    @test has_julia_dependabot_entry("""
        updates:
          - package-ecosystem: "julia"
            directory: "/test"
    """, "/test")
    @test has_julia_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directory: /test/
    """, "/test")
    @test has_julia_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directories: ["/", "/test"]
    """, "/test")
    @test has_julia_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directories:
              - "/"
              - "/test"
    """, "/test")

    @test !has_julia_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directory: /testing
    """, "/test")
    @test !has_julia_dependabot_entry("""
        updates:
          - package-ecosystem: github-actions
            directory: "/test"
    """, "/test")
    @test !has_github_actions_dependabot_entry("""
        updates:
          - package-ecosystem: julia
            directory: "/"
    """)
end
