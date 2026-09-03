# Numeric filters.
#
# Liquid coerces freely here: a non-numeric input is 0, and so is a non-numeric
# argument, so `{{ "hello" | plus: 1 }}` is 1 rather than an error.  Two filters
# are stricter, because there is no sensible answer to fall back on:
# `divided_by` and `modulo` reject a non-numeric or zero divisor.
#
# Int and Float stay distinct throughout, because the output shows it:
# `{{ 10 | plus: 2 }}` is "12" but `{{ 10 | plus: 2.0 }}` is "12.0".

# Coerce both operands, promoting to Float if either is one.  `default` is what
# a non-numeric argument becomes.
function numeric_operands(input, argument, default::Int = 0)
    left = to_number(input)
    right = to_number(argument)
    return promote(left === nothing ? 0 : left, right === nothing ? default : right)
end

# Coerce a divisor, refusing anything that is not a usable number.
function numeric_divisor(argument, name::AbstractString)
    value = to_number(argument)
    value === nothing && filter_error("$name needs a number, got $(type_name(argument))")
    value == 0 && filter_error("divide by zero")
    return value
end

# Float arithmetic on decimal inputs accumulates error that the reference
# implementation, which works in decimal, does not show: 10.1 + 2.2 is
# 12.299999999999999 in binary floating point but "12.3" in Liquid.  Rounding
# the *result* of the additive filters to 10 decimal places reproduces the
# decimal answer for the inputs templates realistically carry, without touching
# division, whose long expansions are expected to survive in full.
tidy_decimal(x::Integer) = x
tidy_decimal(x::AbstractFloat) = isfinite(x) ? round(x; digits = 10) : x

"""
    plus(input, argument)

`{{ 10 | plus: 2 }}`.  Non-numeric operands count as 0.
"""
plus(input, argument) = tidy_decimal(+(numeric_operands(input, argument)...))

"""
    minus(input, argument)

`{{ 10 | minus: 2 }}`.  Non-numeric operands count as 0.
"""
minus(input, argument) = tidy_decimal(-(numeric_operands(input, argument)...))

"""
    times(input, argument)

`{{ 5 | times: 2 }}`.  Non-numeric operands count as 0, so the result is 0.
"""
times(input, argument) = tidy_decimal(*(numeric_operands(input, argument)...))

"""
    divided_by(input, argument)

`{{ 10 | divided_by: 2 }}`.

Integer division when both operands are integers, so `{{ 9 | divided_by: 2 }}`
is 4, not 4.5. A divisor that is zero or not a number is an error.
"""
function divided_by(input, argument)
    divisor = numeric_divisor(argument, "divided_by")
    dividend = to_number(input)
    dividend === nothing && (dividend = 0)
    left, right = promote(dividend, divisor)
    return left isa Integer ? div(left, right) : left / right
end

"""
    modulo(input, argument)

`{{ 10 | modulo: 3 }}`.  Like `divided_by`, the divisor must be a usable number.
"""
function modulo(input, argument)
    divisor = numeric_divisor(argument, "modulo")
    dividend = to_number(input)
    dividend === nothing && (dividend = 0)
    left, right = promote(dividend, divisor)
    return tidy_decimal(mod(left, right))
end

"""
    abs_filter(input)

`{{ -5 | abs }}`.  Preserves Int and Float; a non-number is 0.
"""
function abs_filter(input)
    value = to_number(input)
    return value === nothing ? 0 : abs(value)
end

"""
    ceil_filter(input)

`{{ 5.4 | ceil }}`.  Always returns an integer.
"""
function ceil_filter(input)
    value = to_number(input)
    return value === nothing ? 0 : Int(ceil(value))
end

"""
    floor_filter(input)

`{{ 5.4 | floor }}`.  Always returns an integer.
"""
function floor_filter(input)
    value = to_number(input)
    return value === nothing ? 0 : Int(floor(value))
end

"""
    round_filter(input, places = 0)

`{{ 5.666 | round: 1 }}`.

With no argument, or a non-positive one, the result is an integer; with a
positive one it keeps that many decimal places.  A non-numeric argument counts
as 0 places.
"""
function round_filter(input, places = 0)
    value = to_number(input)
    value === nothing && return 0
    digits = to_number(places)
    digits = digits === nothing ? 0 : trunc(Int, digits)
    digits > 0 && return round(float(value); digits)
    digits < 0 && return Int(round(float(value); digits))
    # An integer is already rounded.  Handled separately because
    # `round(Int, ::Integer, ::RoundingMode)` has no method before Julia 1.11.
    value isa Integer && return Int(value)
    # Liquid rounds a half away from zero (2.5 becomes 3); Julia's default
    # rounds halves to even, so the mode has to be given explicitly.
    return round(Int, value, RoundNearestTiesAway)
end

"""
    at_least(input, argument)

`{{ 5 | at_least: 8 }}`, the larger of the two.  Non-numbers count as 0.
"""
at_least(input, argument) = max(numeric_operands(input, argument)...)

"""
    at_most(input, argument)

`{{ 5 | at_most: 8 }}`, the smaller of the two.  Non-numbers count as 0.
"""
at_most(input, argument) = min(numeric_operands(input, argument)...)
