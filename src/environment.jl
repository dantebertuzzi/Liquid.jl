# Configuration: what a template is parsed and rendered against.

"""
    AbstractLoader

Supertype for template loaders.  A loader maps a template name to source text;
implement [`get_source`](@ref) for your own.
"""
abstract type AbstractLoader end

"""
    NullLoader()

A loader that has no templates.  The default, used when templates come from
strings rather than from disk.
"""
struct NullLoader <: AbstractLoader end

"""
    FileSystemLoader(root)

Load templates from files under `root`.

Names are resolved against `root` and checked to stay inside it, so a template
name cannot reach outside the directory with `../`.
"""
struct FileSystemLoader <: AbstractLoader
    root::String
    FileSystemLoader(root::AbstractString) = new(abspath(String(root)))
end

"""
    get_source(loader, name) -> String

The source text of the template called `name`.  Throws `ArgumentError` when the
loader has no such template.
"""
function get_source end

get_source(::NullLoader, name::AbstractString) =
    throw(ArgumentError("no loader configured, cannot load template $(repr(name))"))

function get_source(loader::FileSystemLoader, name::AbstractString)
    path = normpath(joinpath(loader.root, name))
    # Containment check: reject a name that escapes the root, whatever it is
    # spelled with.  This is a security boundary, not a convenience.
    root = endswith(loader.root, Base.Filesystem.path_separator) ?
           loader.root : loader.root * Base.Filesystem.path_separator
    startswith(path, root) ||
        throw(ArgumentError("template name $(repr(name)) escapes the loader root"))
    isfile(path) || throw(ArgumentError("template not found: $(repr(name))"))
    return read(path, String)
end

"""
    Environment(; loader, autoescape, strict_variables, strict_filters)

Configuration shared by the templates parsed against it: which tags and filters
exist, where templates are loaded from, and how strict rendering is.

Each environment owns its own tag and filter registries, copied from the
built-in defaults at construction, so registering a tag in one environment
never affects another.

- `loader`: where [`get_template`](@ref) finds templates.  Default [`NullLoader`](@ref).
- `autoescape`: HTML-escape the result of every output statement.  Default `false`.
- `strict_variables`: raise [`LiquidUndefinedError`](@ref) instead of rendering
  an undefined variable as the empty string.  Default `false`.
- `strict_filters`: raise instead of ignoring an unknown filter.  Default `false`.
"""
struct Environment
    loader::AbstractLoader
    tags::Dict{String,TagDef}
    filters::Dict{String,Any}
    autoescape::Bool
    strict_variables::Bool
    strict_filters::Bool
end

Environment(; loader::AbstractLoader = NullLoader(),
              autoescape::Bool = false,
              strict_variables::Bool = false,
              strict_filters::Bool = false) =
    Environment(loader, default_tags(), default_filters(),
                autoescape, strict_variables, strict_filters)

"""
    Template

A parsed template: its node list, the environment it was parsed against, and
the name it was loaded under (empty for templates parsed from a string).

Parse once and render many times; rendering does not mutate the template.
"""
struct Template
    nodes::Vector{Node}
    env::Environment
    name::String
end

# One process-wide environment backs the `render(source; kwargs...)` shortcut.
# Built in __init__ rather than as a const, because its registries hold
# functions and must not be baked into the precompiled image.
const DEFAULT_ENVIRONMENT = Ref{Environment}()

"""
    default_environment() -> Environment

The environment used by [`render`](@ref) and [`parse_template`](@ref) when none
is given.
"""
default_environment() = DEFAULT_ENVIRONMENT[]
