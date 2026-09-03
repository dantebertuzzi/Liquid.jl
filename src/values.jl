# Runtime values that have no Julia counterpart.
#
# Liquid's `nil` is `nothing`.  `empty` and `blank` are different: they are
# singleton values that compare *equal* to any empty (respectively blank)
# collection or string, which is how `{% if a == empty %}` works.  The
# comparison rules themselves live in the coercion layer; here we only give the
# values a type and a name.

"""
    Empty

The type of [`EMPTY`](@ref), Liquid's `empty` keyword.
"""
struct Empty end

"""
    Blank

The type of [`BLANK`](@ref), Liquid's `blank` keyword.
"""
struct Blank end

"""
    EMPTY

Liquid's `empty` keyword: equal to any empty string, array or mapping.
"""
const EMPTY = Empty()

"""
    BLANK

Liquid's `blank` keyword: equal to any empty or whitespace-only value.
"""
const BLANK = Blank()

Base.show(io::IO, ::Empty) = print(io, "Liquid.EMPTY")
Base.show(io::IO, ::Blank) = print(io, "Liquid.BLANK")
