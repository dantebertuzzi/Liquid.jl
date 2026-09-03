# The opt-in interface by which a user's own type exposes data to templates.
#
# The security rule of this package is that template text never reaches Julia's
# reflection.  A struct is therefore opaque by default: `liquid_properties`
# returns an empty tuple, so every property lookup on it resolves to nil.  The
# author of the type has to name the fields that become visible, and only those
# names are ever passed to `getfield`.

"""
    liquid_properties(::Type{T}) -> Tuple{Vararg{Symbol}}

The fields of `T` that templates may read.  Returns `()` by default, which
makes values of `T` opaque: no field is reachable from a template.

Opt a type in by adding a method:

```julia
struct Product
    name::String
    price::Float64
    cost::Float64      # stays invisible to templates
end

Liquid.liquid_properties(::Type{Product}) = (:name, :price)
```

This is the Julia counterpart of Ruby Liquid's Drops.  Only the symbols
returned here are ever passed to `getfield`, so a hostile template cannot name
a field that the type's author did not list.

See also [`liquid_get`](@ref) and [`@liquid_drop`](@ref).
"""
liquid_properties(::Type) = ()
liquid_properties(x) = liquid_properties(typeof(x))

"""
    liquid_get(obj, key::AbstractString) -> Any

Read the property `key` from `obj`, or `nothing` when there is no such
property.

The default implementation looks `key` up among [`liquid_properties`](@ref) and
reads that field.  Override it to expose computed properties:

```julia
function Liquid.liquid_get(p::Product, key::AbstractString)
    key == "discounted" && return p.price * 0.9
    return invoke(Liquid.liquid_get, Tuple{Any,AbstractString}, p, key)
end
```

Returning `nothing` for an unknown key is what keeps rendering lenient: a
template that asks for a property that does not exist gets nil, not an error.
"""
function liquid_get(obj, key::AbstractString)
    for property in liquid_properties(typeof(obj))
        String(property) == key && return getfield(obj, property)
    end
    return nothing
end

"""
    @liquid_drop T field...

Shorthand for a [`liquid_properties`](@ref) method.

```julia
@liquid_drop Product name price
```

expands to `Liquid.liquid_properties(::Type{Product}) = (:name, :price)`.  Use
the function directly when the property list is computed rather than literal.
"""
macro liquid_drop(T, fields...)
    names = Expr(:tuple, (QuoteNode(f) for f in fields)...)
    return esc(quote
        $(@__MODULE__).liquid_properties(::Type{$T}) = $names
    end)
end
