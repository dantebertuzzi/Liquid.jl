# The lenient layer.
#
# Julia is strict: comparing a String to an Int throws, `nothing` has no
# properties, and there is no implicit conversion.  Liquid is the opposite, and
# rendering a template is not supposed to fail.  Everything that reconciles the
# two lives here, so the rules are in one place and can be tested without a
# template in sight.
#
# The one place Liquid is *not* lenient is order comparison: `{% if '2' > 1 %}`
# raises, while `{% if 'abc' < 'acb' %}` compares two strings happily.

"""
    is_truthy(x) -> Bool

Liquid truthiness: only `false` and nil are false.

Everything else is true, including `0`, the empty string, the empty array and
the empty hash.  Julia's `nothing` and `missing` both stand for Liquid's nil.
"""
is_truthy(::Nothing) = false
is_truthy(::Missing) = false
is_truthy(x::Bool) = x
is_truthy(::Any) = true

"""
    to_liquid_string(x) -> String

Render `x` the way Liquid writes a value into the output.

nil renders as the empty string, booleans as `"true"`/`"false"`, arrays as
their elements concatenated with no separator, and a type the package does not
know renders as the empty string rather than leaking its Julia representation.
Add a method for your own type to change that.
"""
to_liquid_string(::Nothing) = ""
to_liquid_string(::Missing) = ""
to_liquid_string(::Empty) = ""
to_liquid_string(::Blank) = ""
to_liquid_string(x::Bool) = x ? "true" : "false"
to_liquid_string(x::AbstractString) = String(x)
to_liquid_string(x::Integer) = string(x)
to_liquid_string(x::AbstractFloat) = string(x)
to_liquid_string(x::Number) = string(x)
to_liquid_string(x::AbstractVector) = join(to_liquid_string(v) for v in x)
# A mapping has a printed form, unlike an array: the reference implementation
# renders an empty hash as "{}".  The non-empty shape follows Ruby's Hash#to_s.
to_liquid_string(d::AbstractDict) =
    "{" * join(("$(_hash_part(k))=>$(_hash_part(v))" for (k, v) in d), ", ") * "}"
_hash_part(x::AbstractString) = "\"" * x * "\""
_hash_part(x) = to_liquid_string(x)
to_liquid_string(x::AbstractRange) = join(to_liquid_string(v) for v in x)
# Anything else, a user struct included, stays silent unless it opts in.
to_liquid_string(::Any) = ""

"""
    to_number(x) -> Union{Int,Float64,Nothing}

Coerce `x` to a number for arithmetic filters, or `nothing` when it cannot be
read as one.  Liquid parses a leading number out of a string and treats nil as
zero-ish, which is why callers usually fall back to `0`.
"""
to_number(x::Integer) = Int(x)
to_number(x::AbstractFloat) = Float64(x)
to_number(::Bool) = nothing          # a Bool is not a number in Liquid
to_number(::Nothing) = nothing
to_number(::Missing) = nothing
function to_number(x::AbstractString)
    m = match(r"^\s*-?[0-9]+(\.[0-9]+)?", x)
    m === nothing && return nothing
    text = strip(m.match)
    return occursin('.', text) ? parse(Float64, text) : parse(Int, text)
end
to_number(::Any) = nothing

"""
    is_blank(x) -> Bool

Whether `x` counts as Liquid's `blank`: nil, `false`, an empty or
whitespace-only string, or an empty collection.
"""
is_blank(::Nothing) = true
is_blank(::Missing) = true
is_blank(x::Bool) = !x
is_blank(x::AbstractString) = all(isspace, x)
is_blank(x::Union{AbstractVector,AbstractDict,AbstractRange,Tuple}) = isempty(x)
is_blank(::Any) = false

"""
    is_empty(x) -> Bool

Whether `x` counts as Liquid's `empty`: an empty string or an empty collection.
Unlike [`is_blank`](@ref), nil and `false` are not empty, and whitespace is not
empty either.
"""
is_empty(x::AbstractString) = isempty(x)
is_empty(x::Union{AbstractVector,AbstractDict,AbstractRange,Tuple}) = isempty(x)
is_empty(::Any) = false

"""
    liquid_equal(a, b) -> Bool

Liquid's `==`.  Never raises: values of unrelated types are simply unequal.

nil equals nil (and `missing`), numbers compare across Int and Float, and the
`empty` and `blank` keywords compare equal to any value that is empty or blank
respectively.
"""
liquid_equal(::Nothing, ::Nothing) = true
liquid_equal(::Nothing, ::Missing) = true
liquid_equal(::Missing, ::Nothing) = true
liquid_equal(::Missing, ::Missing) = true
liquid_equal(::Nothing, ::Any) = false
liquid_equal(::Any, ::Nothing) = false
liquid_equal(::Missing, ::Any) = false
liquid_equal(::Any, ::Missing) = false

liquid_equal(::Empty, b) = is_empty(b)
liquid_equal(a, ::Empty) = is_empty(a)
liquid_equal(::Empty, ::Empty) = true
liquid_equal(::Blank, b) = is_blank(b)
liquid_equal(a, ::Blank) = is_blank(a)
liquid_equal(::Blank, ::Blank) = true
# Spelled out to keep the Empty/Blank pairs from being ambiguous.
liquid_equal(::Empty, ::Blank) = false
liquid_equal(::Blank, ::Empty) = false
liquid_equal(::Empty, ::Nothing) = false
liquid_equal(::Nothing, ::Empty) = false
liquid_equal(::Blank, ::Nothing) = true
liquid_equal(::Nothing, ::Blank) = true
liquid_equal(::Empty, ::Missing) = false
liquid_equal(::Missing, ::Empty) = false
liquid_equal(::Blank, ::Missing) = true
liquid_equal(::Missing, ::Blank) = true

liquid_equal(a::Bool, b::Bool) = a == b
liquid_equal(::Bool, ::Number) = false      # true == 1 is false in Liquid
liquid_equal(::Number, ::Bool) = false
liquid_equal(a::Number, b::Number) = a == b
liquid_equal(a::AbstractString, b::AbstractString) = a == b
liquid_equal(a::AbstractVector, b::AbstractVector) =
    length(a) == length(b) && all(liquid_equal(x, y) for (x, y) in zip(a, b))
liquid_equal(a::AbstractDict, b::AbstractDict) =
    length(a) == length(b) &&
    all(haskey(b, k) && liquid_equal(v, b[k]) for (k, v) in a)
liquid_equal(a, b) = a === b

"""
    liquid_less(a, b) -> Bool

Liquid's `<`.  Both operands must be numbers, or both strings; anything else
raises, and the caller turns that into a [`LiquidArgumentError`](@ref).

This is the one deliberate exception to the package's leniency, and it matches
the reference implementation: `{% if 'abc' < 'acb' %}` is fine, `{% if '2' > 1 %}`
is an error.
"""
liquid_less(a::Number, b::Number) = a < b
liquid_less(a::AbstractString, b::AbstractString) = a < b
liquid_less(a::Bool, b::Bool) = throw(IncomparableValues(a, b))
liquid_less(a, b) = throw(IncomparableValues(a, b))

"""
    IncomparableValues(left, right)

Internal signal that an order comparison could not be made, because the two
values are not both numbers or both strings.

[`evaluate`](@ref) catches it and rethrows a [`LiquidArgumentError`](@ref)
carrying the template position, which the comparison itself does not know.
"""
struct IncomparableValues <: Exception
    left::Any
    right::Any
end

"""
    liquid_contains(haystack, needle) -> Bool

Liquid's `contains`: substring search for strings, membership for arrays.
Anything else, nil included, contains nothing.
"""
function liquid_contains(haystack, needle)
    # nil, missing and booleans are never contained in anything, not even in an
    # array that holds them: `{% if a contains nil %}` is FALSE.  Checked here
    # rather than by dispatch, which would be ambiguous against the haystack
    # methods below.
    (needle === nothing || needle === missing || needle isa Bool) && return false
    return contains_value(haystack, needle)
end

contains_value(haystack::AbstractString, needle::AbstractString) = occursin(needle, haystack)
contains_value(haystack::AbstractString, needle) = occursin(to_liquid_string(needle), haystack)
contains_value(haystack::AbstractVector, needle) =
    any(liquid_equal(item, needle) for item in haystack)
contains_value(::Any, ::Any) = false

"""
    compare(op::CompareOp, a, b) -> Bool

Apply a parsed comparison operator.  Order comparisons may throw
[`IncomparableValues`](@ref).
"""
function compare(op::CompareOp, a, b)
    op === EQ && return liquid_equal(a, b)
    op === NE && return !liquid_equal(a, b)
    op === CONTAINS && return liquid_contains(a, b)
    # An order comparison against `empty` or `blank` is simply false, in both
    # directions and never an error: `{% if blank <= 1 or blank >= 1 %}` is
    # FALSE.  Note this cannot be expressed by negating the opposite operator.
    if a isa Empty || a isa Blank || b isa Empty || b isa Blank
        return false
    end
    op === LT && return liquid_less(a, b)
    op === GT && return liquid_less(b, a)
    op === LE && return !liquid_less(b, a)
    op === GE && return !liquid_less(a, b)
    error("unreachable: unhandled comparison operator $op")
end
