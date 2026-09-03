```@meta
CurrentModule = Liquid
```

# Extending

Tags and filters live in registries owned by an [`Environment`](@ref), copied
from the built-in defaults when it is constructed. Registering into one
environment never affects another.

## Custom filters

A filter is an ordinary Julia function called as `f(input, args...; kwargs...)`.
There is nothing to subclass and no wrapper to write.

```jldoctest filters
julia> using Liquid

julia> shout(input) = uppercase(string(input)) * "!";

julia> env = Environment();

julia> Liquid.register_filter!(env.filters, "shout", shout);

julia> render(parse_template("{{ name | shout }}"; env); name = "world")
"WORLD!"
```

Arguments from the template arrive as ordinary arguments:

```jldoctest filters
julia> repeat_filter(input, n) = repeat(string(input), Int(n));

julia> Liquid.register_filter!(env.filters, "repeat", repeat_filter);

julia> render(parse_template("{{ 'ab' | repeat: 3 }}"; env))
"ababab"
```

A filter that needs the render context declares it, and is then called as
`f(ctx, input, args...)`:

```julia
Liquid.needs_context(::typeof(myfilter)) = true
```

Rejecting an input is done with [`filter_error`](@ref); the position in the
template is added for you, since the filter has no way to know it.

Calling a filter with arguments it does not accept is an error. An *unknown*
filter is a no-op by default, and an error when the environment sets
`strict_filters = true`.

## Custom tags

A tag is a [`TagDef`](@ref): a name, a parse function, and the names of the tags
that belong to its block. The parse function receives the [`Parser`](@ref)
positioned just after the tag token and returns a [`Node`](@ref).

Give the node a `render_node` method and it is renderable.

```jldoctest tags
julia> using Liquid

julia> struct ShoutNode <: Liquid.Node
           body::Vector{Liquid.Node}
       end

julia> function parse_shout(p::Liquid.Parser, tok::Liquid.Token)
           body, _ = Liquid.parse_block!(p, ["endshout"])
           return ShoutNode(body)
       end;

julia> function Liquid.render_node(io::IO, node::ShoutNode, ctx::Liquid.Context)
           inner = IOBuffer()
           Liquid.render_nodes(inner, node.body, ctx)
           print(io, uppercase(String(take!(inner))))
       end;

julia> env = Environment();

julia> Liquid.register_tag!(env.tags,
           Liquid.TagDef("shout", parse_shout; inner = ["endshout"]));

julia> render(parse_template("{% shout %}hello {{ name }}{% endshout %}"; env);
              name = "world")
"HELLO WORLD"
```

The `inner` list is what lets the parser report a stray `{% endshout %}` as an
unexpected tag rather than an unknown one.

### What a parse function may use

[`parse_block!`](@ref) reads a body up to a closing tag, [`tag_args`](@ref)
gives the tag's arguments with their position, and [`syntax_error`](@ref)
reports a problem against the template.

For tags that take operands there are three expression entry points:
[`parse_value`](@ref) for a bare value, [`parse_condition`](@ref) for an
`if`-style condition, and [`parse_filtered`](@ref) for a value with a filter
chain.

### Blank nodes

A block whose body can only produce whitespace has its output dropped, so
`{% if true %}  {% endif %}` renders nothing. A node type from outside the
package is assumed to produce output; give it an [`is_blank_node`](@ref) method
returning `true` if it does not.

## Custom loaders

Subtype [`AbstractLoader`](@ref) and implement [`get_source`](@ref):

```julia
struct DictLoader <: Liquid.AbstractLoader
    templates::Dict{String,String}
end

function Liquid.get_source(loader::DictLoader, name::AbstractString)
    haskey(loader.templates, name) ||
        throw(ArgumentError("template not found: $(repr(name))"))
    return loader.templates[name]
end
```

[`FileSystemLoader`](@ref) checks that a resolved name stays inside its root, so
a template name cannot escape the directory with `../`. A loader of your own
that touches the filesystem should do the same.
