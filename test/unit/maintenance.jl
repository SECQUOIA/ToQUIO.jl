using TOML

const TEST_PROJECT_DEPS = Dict(
    "Test" => "8dfed614-e22c-5e08-85e1-65c5234f0b40",
    "TOML" => "fa267f1f-6049-4f14-aa54-33bafae1ed76",
    "ToQUIO" => "c8c7c8a1-01ab-43fa-b80d-8804f80d4aae",
)

const DOCS_PROJECT_DEPS = Dict(
    "Documenter" => "e30172f5-a6a5-5a46-863b-614d45cd2de4",
    "ToQUIO" => "c8c7c8a1-01ab-43fa-b80d-8804f80d4aae",
)

const SUPPORTED_JULIA_VERSIONS = ("1.10", "1")
# Keep this in sync with Project.toml until the first registered tag is cut.
const INITIAL_REGISTRATION_VERSION = "0.1.0"

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

function leading_whitespace_length(value::AbstractString)
    prefix = match(r"""^\s*""", value)
    return length(prefix.match)
end

function ci_julia_versions(config::AbstractString)
    versions = String[]
    in_julia_version = false
    julia_version_indent = 0

    for raw_line in split(config, '\n')
        line = strip(raw_line)
        isempty(line) && continue

        if in_julia_version
            if leading_whitespace_length(raw_line) <= julia_version_indent &&
               !startswith(line, "-")
                in_julia_version = false
            else
                item = match(r"""^-\s*(.+?)\s*$""", line)
                if item !== nothing
                    push!(versions, normalized_yaml_scalar(item.captures[1]))
                    continue
                end
            end
        end

        julia_version = match(r"""^(\s*)julia-version:\s*(.*?)\s*$""", raw_line)
        if julia_version !== nothing
            julia_version_indent = length(julia_version.captures[1])
            inline_versions = strip(julia_version.captures[2])
            if isempty(inline_versions)
                in_julia_version = true
            else
                append!(versions, normalized_yaml_scalar.(inline_yaml_values(inline_versions)))
                in_julia_version = false
            end
        end
    end

    return versions
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

    @test project["version"] == INITIAL_REGISTRATION_VERSION
    @test compat["julia"] == first(SUPPORTED_JULIA_VERSIONS)
    @test compat["LinearAlgebra"] == "1"
    @test compat["MathOptInterface"] == "1"
end

@testset "Release workflow policy" begin
    tagbot_workflow = joinpath(pkgdir(ToQUIO), ".github", "workflows", "TagBot.yml")
    @test isfile(tagbot_workflow)

    tagbot_config = read(tagbot_workflow, String)
    @test occursin(r"(?m)^\s*issue_comment\s*:", tagbot_config)
    @test occursin(r"(?m)^\s*workflow_dispatch\s*:", tagbot_config)
    @test occursin(r"(?m)^\s*contents:\s*write\s*$", tagbot_config)
    @test occursin(r"(?m)^\s*issues:\s*read\s*$", tagbot_config)
    @test occursin("github.actor == 'JuliaTagBot'", tagbot_config)
    @test occursin("JuliaRegistries/TagBot@v1", tagbot_config)
    @test occursin(raw"token: ${{ secrets.GITHUB_TOKEN }}", tagbot_config)
    @test occursin(raw"ssh: ${{ secrets.SSH_KEY }}", tagbot_config)
end

@testset "Release documentation policy" begin
    readme = read(joinpath(pkgdir(ToQUIO), "README.md"), String)
    contributing = read(joinpath(pkgdir(ToQUIO), "CONTRIBUTING.md"), String)

    @test occursin("targeting registration in the Julia General registry", readme)
    @test occursin("After registration, released versions will be installable", readme)
    @test occursin("""Pkg.add("ToQUIO")""", readme)
    @test occursin("version = \"$(INITIAL_REGISTRATION_VERSION)\"", readme)

    @test occursin("## Release Process", contributing)
    @test occursin("JuliaRegistrator", contributing)
    @test occursin("TagBot", contributing)
    @test occursin("@JuliaRegistrator register", contributing)
    @test occursin("SSH_KEY", contributing)
    @test occursin("workflow_dispatch", contributing)
    @test occursin("Release checklist", contributing)
    @test occursin("Pkg.test()", contributing)
    @test occursin("docs/make.jl --skip-deploy", contributing)
    @test occursin("version = \"$(INITIAL_REGISTRATION_VERSION)\"", contributing)
end

@testset "CI workflow policy" begin
    ci_workflow = joinpath(pkgdir(ToQUIO), ".github", "workflows", "ci.yml")
    @test isfile(ci_workflow)

    ci_config = read(ci_workflow, String)
    @test occursin(r"(?m)^\s*pull_request\s*:", ci_config)
    @test occursin("julia-actions/setup-julia", ci_config)
    @test occursin("julia-actions/julia-runtest", ci_config)
    @test ci_julia_versions(ci_config) == collect(SUPPORTED_JULIA_VERSIONS)
end

@testset "Documentation environment policy" begin
    project = TOML.parsefile(joinpath(pkgdir(ToQUIO), "docs", "Project.toml"))

    @test project["deps"] == DOCS_PROJECT_DEPS
    @test project["compat"]["Documenter"] == "1"
    @test project["compat"]["julia"] == first(SUPPORTED_JULIA_VERSIONS)

    make_jl = read(joinpath(pkgdir(ToQUIO), "docs", "make.jl"), String)
    @test occursin("--skip-deploy", make_jl)
    @test occursin("deploydocs", make_jl)
    @test occursin("push_preview = false", make_jl)
end

@testset "Documentation workflow policy" begin
    docs_workflow = joinpath(pkgdir(ToQUIO), ".github", "workflows", "documentation.yml")
    @test isfile(docs_workflow)

    docs_config = read(docs_workflow, String)
    @test occursin(r"(?m)^\s*pull_request\s*:", docs_config)
    @test occursin(r"(?m)^\s*workflow_dispatch\s*:", docs_config)
    @test occursin("actions/checkout@v6", docs_config)
    @test occursin("julia-actions/setup-julia@v3", docs_config)
    @test occursin("github.event_name == 'pull_request'", docs_config)
    @test occursin("github.event_name != 'pull_request'", docs_config)
    @test occursin(r"(?m)^\s*group: docs-deploy\s*$", docs_config)
    @test occursin(r"(?m)^\s*cancel-in-progress: false\s*$", docs_config)
    @test occursin(r"(?m)^\s*run: julia --project=docs docs/make\.jl --skip-deploy\s*$", docs_config)
    @test occursin(r"(?m)^\s*run: julia --project=docs docs/make\.jl\s*$", docs_config)
end

@testset "CI Julia version detection" begin
    @test ci_julia_versions("""
        matrix:
          julia-version:
            - '1.10'
            - '1'
    """) == ["1.10", "1"]
    @test ci_julia_versions("""
        matrix:
          julia-version: ["1.10", "1"]
    """) == ["1.10", "1"]
    @test isempty(ci_julia_versions("""
        matrix:
          unrelated:
            - '1.10'
            - '1'
    """))
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
        @test has_julia_dependabot_entry(config, "/docs")
        @test has_github_actions_dependabot_entry(config)
    else
        # Dormant until #8 adds a Dependabot config; synthetic tests below
        # cover the detector meanwhile.
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
