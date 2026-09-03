# The public entry points.

"""
    parse_template(source; env = default_environment(), name = "") -> Template

Parse `source` into a reusable [`Template`](@ref).

Parse once and render many times when a template is used more than once;
parsing is the expensive half and rendering does not mutate the result.

```julia
tmpl = parse_template("Hello, {{ name }}!")
render(tmpl; name = "World")
render(tmpl; name = "Liquid")
```
"""
function parse_template(source::AbstractString; env::Environment = default_environment(),
                        name::AbstractString = "")
    nodes = parse_nodes(source, env.tags; template_name = name)
    return Template(nodes, env, String(name))
end

"""
    get_template(env, name) -> Template

Load and parse the template called `name` through `env`'s loader.

```julia
env = Environment(loader = FileSystemLoader("./templates"))
tmpl = get_template(env, "letter.liquid")
```
"""
function get_template(env::Environment, name::AbstractString)
    source = get_source(env.loader, name)
    return parse_template(source; env, name)
end

"""
    to_globals(data) -> Dict{String,Any}

Normalise the caller's data into the root scope.

Accepts a `NamedTuple`, a `Dict` keyed by `String` or `Symbol`, any other
`AbstractDict`, or nothing at all.  Keys become strings because that is what a
template names them by.
"""
to_globals(::Nothing) = Dict{String,Any}()
to_globals(nt::NamedTuple) = Dict{String,Any}(String(k) => v for (k, v) in pairs(nt))
to_globals(d::AbstractDict) = Dict{String,Any}(to_globals_key(k) => v for (k, v) in d)
to_globals(d::Dict{String,Any}) = d

to_globals_key(k::AbstractString) = String(k)
to_globals_key(k::Symbol) = String(k)
to_globals_key(k) = to_liquid_string(k)

"""
    render(io::IO, template::Template, data)

Render `template` into `io`.  This is the primitive the other methods build on;
use it to stream a large result instead of building a string.
"""
function render(io::IO, template::Template, data)
    ctx = Context(template.env, to_globals(data); template_name = template.name)
    render_nodes(io, template.nodes, ctx)
    return nothing
end

"""
    render(template::Template, data) -> String
    render(template::Template; kwargs...) -> String
    render(source::AbstractString, data) -> String
    render(source::AbstractString; kwargs...) -> String

Render a template and return the result.

`data` may be a `NamedTuple`, a `Dict` keyed by strings or symbols, or keyword
arguments.  Given a string, the template is parsed against
[`default_environment`](@ref) and rendered once; parse it yourself with
[`parse_template`](@ref) when it will be reused.

```julia
render("Hello, {{ name }}!"; name = "World")
render("{{ a.b }}", Dict("a" => Dict("b" => 1)))
```
"""
function render(template::Template, data)
    io = IOBuffer()
    render(io, template, data)
    return String(take!(io))
end

render(template::Template; kwargs...) = render(template, values(kwargs))

render(source::AbstractString, data; env::Environment = default_environment()) =
    render(parse_template(source; env), data)

render(source::AbstractString; kwargs...) =
    render(parse_template(source), values(kwargs))
