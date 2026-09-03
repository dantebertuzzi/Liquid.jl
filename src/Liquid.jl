"""
    Liquid

A pure-Julia implementation of the Liquid template language.

Templates are processed in three separate stages, each usable on its own:
[`tokenize`](@ref) turns source into tokens, the parser turns tokens into an
AST of `Node`s, and the renderer walks that AST against a context object.
Rendering never evaluates Julia code from template text.
"""
module Liquid

include("errors.jl")
include("lexer.jl")
include("values.jl")
include("exprlexer.jl")
include("expressions.jl")
include("ast.jl")
include("parser.jl")
include("tags/control.jl")
include("tags/iteration.jl")
include("tags/variable.jl")
include("tags/misc.jl")
include("coercion.jl")
include("drops.jl")
include("filters.jl")
include("environment.jl")
include("context.jl")
include("eval.jl")
include("render.jl")

# The filter implementations come after the render layer because they use the
# value model defined there (resolve_key, type_name).  default_filters() only
# references them when it is called, so the registry above is unaffected.
include("filters/numbers.jl")
include("filters/strings.jl")
include("filters/arrays.jl")
include("filters/misc.jl")
include("filters/date.jl")
include("api.jl")

function __init__()
    DEFAULT_ENVIRONMENT[] = Environment()
    return nothing
end

export render, parse_template, get_template, Environment, Template,
       FileSystemLoader, NullLoader, @liquid_drop

end # module Liquid
