```@meta
CurrentModule = Liquid
```

# Passing data

## Accepted shapes

Data reaches a template as keyword arguments, a `NamedTuple`, or a `Dict` keyed
by strings or symbols. Keys become strings, because that is how a template names
them.

```jldoctest
julia> using Liquid

julia> render("{{ x }}"; x = 1)
"1"

julia> render("{{ x }}", (x = 1,))
"1"

julia> render("{{ x }}", Dict("x" => 1))
"1"

julia> render("{{ x }}", Dict(:x => 1))
"1"
```

Nested values keep their own type, so a `Dict` inside a `NamedTuple` works, and
an ordered dictionary iterates in its own order.

## Lookups

Properties are reached with a dot or a subscript. **Subscripts are 0-based**,
and count from the end when negative.

```jldoctest
julia> using Liquid

julia> data = Dict("a" => Dict("b" => Dict("c" => 42)));

julia> render("{{ a.b.c }}", data)
"42"

julia> render("{{ a['b']['c'] }}", data)
"42"

julia> render("{{ xs[0] }} {{ xs[2] }} {{ xs[-1] }}", Dict("xs" => [10, 20, 30]))
"10 30 30"
```

A key that is not a valid identifier is reached by writing the subscript with no
root at all:

```jldoctest
julia> using Liquid

julia> render("{{ [\"a b\"] }}", Dict("a b" => "ok"))
"ok"
```

## Virtual properties

Collections answer to `size`, `first` and `last` without those keys existing.
A real key of the same name always wins.

```jldoctest
julia> using Liquid

julia> render("{{ s.size }} {{ s.first }} {{ s.last }}"; s = "hello")
"5 h o"

julia> render("{{ a.size }} {{ a.first }} {{ a.last }}"; a = [3, 2, 1])
"3 3 1"

julia> render("{{ o.first }}", Dict("o" => Dict("first" => 99)))
"99"
```

A mapping's `first` is its first `[key, value]` pair, and a mapping has no
virtual `last`.

## Exposing your own types

A struct is **opaque by default**. Until its author says otherwise, every
property lookup on it resolves to nil — there is no reflection fallback, so a
template cannot name a field that was not listed.

```jldoctest drops
julia> using Liquid

julia> struct Product
           title::String
           price::Float64
           cost::Float64
       end

julia> product = Product("widget", 9.99, 3.00);

julia> render("[{{ p.title }}]"; p = product)
"[]"
```

Opt in with [`@liquid_drop`](@ref), naming exactly the fields templates may
read. This is the Julia counterpart of Ruby Liquid's Drops.

```jldoctest drops
julia> Liquid.@liquid_drop Product title price

julia> render("{{ p.title }} costs {{ p.price }}"; p = product)
"widget costs 9.99"

julia> render("[{{ p.cost }}]"; p = product)
"[]"
```

The macro is sugar for a [`liquid_properties`](@ref) method; write that directly
when the list is computed rather than literal:

```julia
Liquid.liquid_properties(::Type{Product}) = (:title, :price)
```

For a computed property, add a [`liquid_get`](@ref) method and fall back to the
default for everything else:

```jldoctest drops
julia> function Liquid.liquid_get(p::Product, key::AbstractString)
           key == "margin" && return p.price - p.cost
           return invoke(Liquid.liquid_get, Tuple{Any,AbstractString}, p, key)
       end;

julia> render("{{ p.margin }}"; p = product)
"6.99"
```

## Rendering to an IO

[`render`](@ref) with an `IO` as its first argument writes directly instead of
building a string, which is what you want for a large result.

```jldoctest
julia> using Liquid

julia> io = IOBuffer();

julia> render(io, parse_template("{{ x }}!"), Dict("x" => "hi"));

julia> String(take!(io))
"hi!"
```
