# Render-time state: the scope stack, the loop objects, and how a name in a
# template becomes a value.

"""
    Undefined

The type of [`UNDEFINED`](@ref).
"""
struct Undefined end

"""
    UNDEFINED

Internal marker for "this name does not exist", as distinct from a name that
exists and holds nil.  The distinction only matters for `strict_variables`;
by the time a value reaches the output it has become `nothing`.
"""
const UNDEFINED = Undefined()

"""
    ForLoop

The `forloop` object exposed inside a `{% for %}` body.

Mutated in place as the loop advances rather than rebuilt per iteration; a
template can only read it, never hold on to it.
"""
mutable struct ForLoop
    name::String
    index0::Int
    length::Int
    parentloop::Union{Nothing,ForLoop}
end

"""
    Context

Everything rendering needs besides the AST.

`scopes` is a stack, innermost last; `scopes[1]` holds the caller's data and is
also where `{% assign %}` writes, which is why an assignment inside a loop
outlives the loop.  `counters` is a separate namespace for `increment` and
`decrement`, so `{% assign a = 5 %}{% increment a %}` prints 0, not 5.
`interrupt` carries a pending `break` or `continue` up to the enclosing loop.
`cycles` remembers how far each `{% cycle %}` group has advanced, and
`loop_positions` how far each named loop got, which is what `offset: continue`
resumes from.
"""
mutable struct Context
    env::Environment
    scopes::Vector{Dict{String,Any}}
    counters::Dict{String,Int}
    cycles::Dict{String,Int}
    interrupt::Symbol
    template_name::String
    loop_positions::Dict{String,Int}
end

function Context(env::Environment, globals::Dict{String,Any};
                 template_name::AbstractString = "")
    Context(env, Dict{String,Any}[globals], Dict{String,Int}(), Dict{String,Int}(),
            :none, String(template_name), Dict{String,Int}())
end

push_scope!(ctx::Context) = (push!(ctx.scopes, Dict{String,Any}()); ctx)
pop_scope!(ctx::Context) = (pop!(ctx.scopes); ctx)

"Set a name in the innermost scope (loop variables, `capture` results)."
set_local!(ctx::Context, name::AbstractString, value) =
    (ctx.scopes[end][String(name)] = value; ctx)

"""
    set_global!(ctx, name, value)

Set a name in the outermost scope.  `{% assign %}` uses this: in Liquid an
assignment is visible after the block it was made in.
"""
set_global!(ctx::Context, name::AbstractString, value) =
    (ctx.scopes[1][String(name)] = value; ctx)

"""
    lookup(ctx, name) -> Any

Find `name` in the scope stack, innermost first, or [`UNDEFINED`](@ref).
"""
function lookup(ctx::Context, name::AbstractString)
    for i in lastindex(ctx.scopes):-1:firstindex(ctx.scopes)
        scope = ctx.scopes[i]
        haskey(scope, name) && return scope[name]
    end
    # A counter is readable as a variable, but only when no variable shadows it:
    # `{% increment foo %} {{ foo }}` prints "0 1", while
    # `{% assign foo = 5 %}{% increment foo %} {{ foo }}` prints "0 5".
    haskey(ctx.counters, name) && return ctx.counters[name]
    return UNDEFINED
end

"The innermost `forloop`, or nothing when not inside a loop."
function current_forloop(ctx::Context)
    value = lookup(ctx, "forloop")
    return value isa ForLoop ? value : nothing
end

# ---------------------------------------------------------------------------
# Property resolution
# ---------------------------------------------------------------------------

"""
    resolve_key(value, key) -> Any

Read `key` from `value`, returning [`UNDEFINED`](@ref) when there is nothing
there.  `key` is a `String` for a property and an `Int` for a subscript.

Collections carry virtual properties (`size`, `first`, `last`) that a real key
of the same name shadows: for `{"first": 99}`, `.first` is 99, not the first
pair.  Mappings have `first` and `size` but no virtual `last`, matching the
reference implementation.
"""
function resolve_key end

# nil has no properties, and asking for one is not an error.
resolve_key(::Nothing, key) = UNDEFINED
resolve_key(::Missing, key) = UNDEFINED
resolve_key(::Undefined, key) = UNDEFINED

function resolve_key(d::AbstractDict, key)
    # A real key always wins over a virtual property.
    haskey(d, key) && return d[key]
    if key isa AbstractString
        # Accept Dict{Symbol,Any} without forcing the caller to convert.
        sym = Symbol(key)
        haskey(d, sym) && return d[sym]
        key == "size" && return length(d)
        # `first` yields the first key/value pair, which is why
        # `{{ obj.first | join: '#' }}` renders "a#1".
        if key == "first"
            isempty(d) && return UNDEFINED
            k, v = first(d)
            return Any[k, v]
        end
    end
    return UNDEFINED
end

function resolve_key(v::AbstractVector, key)
    if key isa Integer
        index = liquid_index(Int(key), length(v))
        return checkbounds(Bool, v, index) ? v[index] : UNDEFINED
    elseif key isa AbstractString
        key == "size" && return length(v)
        key == "first" && return isempty(v) ? UNDEFINED : first(v)
        key == "last" && return isempty(v) ? UNDEFINED : last(v)
    end
    return UNDEFINED
end

function resolve_key(r::AbstractRange, key)
    if key isa Integer
        index = liquid_index(Int(key), length(r))
        return checkbounds(Bool, r, index) ? r[index] : UNDEFINED
    elseif key isa AbstractString
        key == "size" && return length(r)
        key == "first" && return isempty(r) ? UNDEFINED : first(r)
        key == "last" && return isempty(r) ? UNDEFINED : last(r)
    end
    return UNDEFINED
end

function resolve_key(s::AbstractString, key)
    if key isa AbstractString
        key == "size" && return length(s)
        key == "first" && return isempty(s) ? UNDEFINED : string(first(s))
        key == "last" && return isempty(s) ? UNDEFINED : string(last(s))
    end
    return UNDEFINED
end

function resolve_key(loop::ForLoop, key)
    key isa AbstractString || return UNDEFINED
    key == "index0"     && return loop.index0
    key == "index"      && return loop.index0 + 1
    key == "rindex"     && return loop.length - loop.index0
    key == "rindex0"    && return loop.length - loop.index0 - 1
    key == "first"      && return loop.index0 == 0
    key == "last"       && return loop.index0 == loop.length - 1
    key == "length"     && return loop.length
    key == "name"       && return loop.name
    key == "parentloop" && return loop.parentloop === nothing ? UNDEFINED : loop.parentloop
    return UNDEFINED
end

# Any other value: the user's own type, through the opt-in drop interface.
# Never reflection, so a struct that has not opted in stays opaque.
function resolve_key(obj, key)
    key isa AbstractString || return UNDEFINED
    value = liquid_get(obj, key)
    return value === nothing ? UNDEFINED : value
end

"""
    liquid_index(key, n) -> Int

Translate a Liquid subscript into a Julia index.  Liquid subscripts are 0-based
and count from the end when negative, so with two elements `[-2]` is the first
one and `[-1]` the last.
"""
liquid_index(key::Int, n::Int) = key < 0 ? n + key + 1 : key + 1

"""
    to_lookup_key(value) -> Union{String,Int}

Normalise an evaluated subscript into a key: integers index, everything else
is looked up by its string form, so `a[b]` works whatever `b` holds.
"""
to_lookup_key(value::Integer) = value isa Bool ? to_liquid_string(value) : Int(value)
to_lookup_key(value::AbstractString) = String(value)
to_lookup_key(value) = to_liquid_string(value)
