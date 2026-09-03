# Filter registry.
#
# A filter is an ordinary Julia function called as `f(input, args...; kwargs...)`.
# The few filters that need the render context opt in through `needs_context`,
# and are then called as `f(ctx, input, args...)`.  Keeping the common case a
# plain function means a user-defined filter is just a function.

"""
    FilterError(msg)

Internal signal raised by a filter that was given something it cannot work
with, such as `{{ 10 | divided_by: 0 }}`.  [`apply_filter`](@ref) catches it and
rethrows it as a [`LiquidArgumentError`](@ref) carrying the template position,
which the filter itself has no way to know.
"""
struct FilterError <: Exception
    msg::String
end

"""
    filter_error(msg)

Raise a [`FilterError`](@ref) from inside a filter.

Use it when a filter is handed something it cannot work with. The template
position is added by [`apply_filter`](@ref), so the message should describe
only what was wrong with the value.
"""
filter_error(msg::AbstractString) = throw(FilterError(String(msg)))

"""
    needs_context(f) -> Bool

Whether the filter function `f` wants the render context as its first argument.

Defaults to `false`, so a filter is a plain function of its input.  Opt in with
`Liquid.needs_context(::typeof(myfilter)) = true` when a filter has to read the
environment or the current scope.
"""
needs_context(::Any) = false

"""
    register_filter!(filters::Dict{String,Any}, name, f)

Add `f` to a filter registry under `name`, replacing any filter already there.
"""
function register_filter!(filters::Dict{String,Any}, name::AbstractString, f)
    filters[String(name)] = f
    return filters
end

"""
    default_filters() -> Dict{String,Any}

A fresh registry holding the built-in filters.  Each [`Environment`](@ref) gets
its own copy, so registering a filter in one never affects another.
"""
function default_filters()
    filters = Dict{String,Any}()
    register_filter!(filters, "plus", plus)
    register_filter!(filters, "minus", minus)
    register_filter!(filters, "times", times)
    register_filter!(filters, "divided_by", divided_by)
    register_filter!(filters, "modulo", modulo)
    register_filter!(filters, "abs", abs_filter)
    register_filter!(filters, "ceil", ceil_filter)
    register_filter!(filters, "floor", floor_filter)
    register_filter!(filters, "round", round_filter)
    register_filter!(filters, "at_least", at_least)
    register_filter!(filters, "at_most", at_most)

    register_filter!(filters, "append", append)
    register_filter!(filters, "prepend", prepend)
    register_filter!(filters, "capitalize", capitalize)
    register_filter!(filters, "downcase", downcase)
    register_filter!(filters, "upcase", upcase)
    register_filter!(filters, "strip", strip_filter)
    register_filter!(filters, "lstrip", lstrip_filter)
    register_filter!(filters, "rstrip", rstrip_filter)
    register_filter!(filters, "strip_newlines", strip_newlines)
    register_filter!(filters, "newline_to_br", newline_to_br)
    register_filter!(filters, "strip_html", strip_html)
    register_filter!(filters, "remove", remove)
    register_filter!(filters, "remove_first", remove_first)
    register_filter!(filters, "replace", replace_filter)
    register_filter!(filters, "replace_first", replace_first)
    register_filter!(filters, "truncate", truncate_filter)
    register_filter!(filters, "truncatewords", truncatewords)

    register_filter!(filters, "join", join_filter)
    register_filter!(filters, "first", first_filter)
    register_filter!(filters, "last", last_filter)
    register_filter!(filters, "size", size_filter)
    register_filter!(filters, "reverse", reverse_filter)
    register_filter!(filters, "compact", compact)
    register_filter!(filters, "uniq", uniq)
    register_filter!(filters, "concat", concat_filter)
    register_filter!(filters, "map", map_filter)
    register_filter!(filters, "split", split_filter)
    register_filter!(filters, "slice", slice_filter)
    register_filter!(filters, "sort", sort_filter)
    register_filter!(filters, "sort_natural", sort_natural)
    register_filter!(filters, "where", where_filter)

    register_filter!(filters, "default", default_filter)
    register_filter!(filters, "escape", escape_filter)
    register_filter!(filters, "escape_once", escape_once)
    register_filter!(filters, "url_encode", url_encode)
    register_filter!(filters, "url_decode", url_decode)
    register_filter!(filters, "date", date_filter)
    return filters
end
