# Array filters.
#
# Liquid is forgiving about what counts as a sequence: a scalar behaves like a
# one-element array for most of these, a mapping behaves like a list of
# [key, value] pairs, and nil behaves like an empty array.  Several filters
# also flatten nested arrays, which is why `join` on `[["a","x"], "b"]` gives
# "a#x#b" rather than showing the nesting.

"""
    to_array(x) -> AbstractVector

The sequence a filter should work on.  A mapping becomes its `[key, value]`
pairs, nil becomes empty, and any other scalar becomes a one-element array.
"""
to_array(x::AbstractVector) = x
to_array(x::AbstractRange) = collect(x)
to_array(x::Tuple) = collect(x)
to_array(d::AbstractDict) = Any[Any[k, v] for (k, v) in d]
to_array(::Nothing) = Any[]
to_array(::Missing) = Any[]
to_array(::Undefined) = Any[]
to_array(x) = Any[x]

"""
    flatten_values(x) -> Vector{Any}

Flatten nested arrays into one list.  `join`, `concat` and `map` all see their
input this way.
"""
function flatten_values(x)
    out = Any[]
    _flatten_into!(out, to_array(x))
    return out
end

function _flatten_into!(out, items)
    for item in items
        if item isa AbstractVector || item isa AbstractRange || item isa Tuple
            _flatten_into!(out, item)
        else
            push!(out, item)
        end
    end
    return out
end

"""
    join_filter(input, separator = " ")

`{{ list | join: ", " }}`.  Nested arrays are flattened first.
"""
join_filter(input, separator = " ") =
    join((to_liquid_string(v) for v in flatten_values(input)), to_liquid_string(separator))

"""
    first_filter(input)

`{{ list | first }}`.  The first character of a string, the first `[key, value]`
pair of a mapping, and nil for a scalar.
"""
first_filter(input::AbstractString) = isempty(input) ? nothing : string(first(input))
first_filter(input::Union{AbstractVector,AbstractRange}) =
    isempty(input) ? nothing : first(input)
first_filter(input::AbstractDict) =
    isempty(input) ? nothing : (kv = first(input); Any[kv[1], kv[2]])
first_filter(::Any) = nothing

"""
    last_filter(input)

`{{ list | last }}`.  Unlike `first`, a mapping has no last: it returns nil.
"""
last_filter(input::AbstractString) = isempty(input) ? nothing : string(last(input))
last_filter(input::Union{AbstractVector,AbstractRange}) =
    isempty(input) ? nothing : last(input)
last_filter(::Any) = nothing

"""
    size_filter(input)

`{{ list | size }}`.  Length of a string, array or mapping; 0 for anything else.
"""
size_filter(input::AbstractString) = length(input)
size_filter(input::Union{AbstractVector,AbstractRange,AbstractDict,Tuple}) = length(input)
size_filter(::Any) = 0

"""
    reverse_filter(input)

`{{ list | reverse }}`.
"""
reverse_filter(input) = reverse(to_array(input))

"""
    compact(input, property = nothing)

`{{ list | compact }}`, dropping nil entries.  With a property name, entries
whose property is nil are dropped instead.
"""
function compact(input, property = nothing)
    items = to_array(input)
    property === nothing && return filter(v -> !(v === nothing || v === missing), items)
    key = to_liquid_string(property)
    return filter(v -> !_missing_property(v, key), items)
end

_missing_property(item, key) =
    (value = resolve_key(item, key)) === UNDEFINED || value === nothing || value === missing

"""
    uniq(input, property = nothing)

`{{ list | uniq }}`, keeping the first of each set of equal entries and
preserving order.  With a property name, entries are compared by that property.
"""
function uniq(input, property = nothing)
    items = to_array(input)
    seen = Any[]
    out = Any[]
    key = property === nothing ? nothing : to_liquid_string(property)
    for item in items
        mark = key === nothing ? item : _property_or_nil(item, key)
        any(s -> liquid_equal(s, mark), seen) && continue
        push!(seen, mark)
        push!(out, item)
    end
    return out
end

_property_or_nil(item, key) =
    (value = resolve_key(item, key)) === UNDEFINED ? nothing : value

"""
    concat_filter(input, other)

`{{ a | concat: b }}`.  Both sides are flattened; the argument must be an
array.
"""
function concat_filter(input, other)
    (other isa AbstractVector || other isa AbstractRange || other isa Tuple) ||
        filter_error("concat needs an array, got $(type_name(other))")
    return vcat(flatten_values(input), flatten_values(other))
end

"""
    map_filter(input, property)

`{{ list | map: 'title' }}`, the named property of every entry.  Entries
without it become nil.
"""
function map_filter(input, property)
    key = to_liquid_string(property)
    # A mapping is one object to read a property from, not a list of pairs.
    input isa AbstractDict && return Any[_property_or_nil(input, key)]

    (input isa AbstractVector || input isa AbstractRange || input isa Tuple ||
     input === nothing || input === missing) ||
        filter_error("map needs an array, got $(type_name(input))")

    items = flatten_values(input)
    all(has_properties, items) ||
        filter_error("map needs entries with properties")
    return Any[_property_or_nil(item, key) for item in items]
end

# Whether a value is the kind of thing a property can be read from at all.
has_properties(::AbstractDict) = true
has_properties(::Union{Number,AbstractString,Bool,Nothing,Missing}) = false
has_properties(x) = !isempty(liquid_properties(typeof(x)))

"""
    split_filter(input, separator)

`{{ "a,b" | split: "," }}`.

An empty separator splits into characters, and trailing empty pieces are
dropped, so `{{ "," | split: "," }}` is empty rather than two empty strings.

A separator of a single space splits on *any* run of whitespace, following
Ruby's `String#split(" ")`: `{{ "a b\nc" | split: " " }}` gives three fields,
not two.
"""
function split_filter(input, separator)
    text = to_liquid_string(input)
    isempty(text) && return String[]
    sep = to_liquid_string(separator)
    parts = isempty(sep) ? [string(c) for c in text] :
            sep == " " ? split(text) : split(text, sep)
    # Ruby's String#split drops trailing empty fields.
    while !isempty(parts) && isempty(parts[end])
        pop!(parts)
    end
    return String[String(p) for p in parts]
end

# `slice` needs real numbers: nil means "use the default", but a non-numeric
# string is an error.
function slice_argument(value, default::Int, name::AbstractString)
    (value === nothing || value === missing) && return default
    number = to_number(value)
    number === nothing && filter_error("$name needs a number, got $(type_name(value))")
    number isa Integer || filter_error("$name needs a whole number")
    return Int(number)
end

"""
    slice_filter(input, start, length = 1)

`{{ "hello" | slice: 1, 3 }}`.

`start` is 0-based and counts from the end when negative.  Works on strings and
arrays; anything else yields nil.
"""
function slice_filter(input, start, length_ = nothing)
    # A missing start is an error, but a missing length falls back to 1.
    (start === nothing || start === missing) &&
        filter_error("slice needs a starting index")
    offset = slice_argument(start, 0, "slice")
    count = slice_argument(length_, 1, "slice")

    if input isa AbstractString
        return _slice_indexable(collect(input), offset, count) |> join
    elseif input isa AbstractVector || input isa AbstractRange
        return _slice_indexable(collect(input), offset, count)
    end
    return nothing
end

function _slice_indexable(items, offset, count)
    n = length(items)
    first_index = offset < 0 ? n + offset + 1 : offset + 1
    first_index < 1 && (first_index = 1)
    (first_index > n || count <= 0) && return empty(items)
    last_index = min(first_index + count - 1, n)
    return items[first_index:last_index]
end

# A total ordering across the mixed types a Liquid array may hold: numbers
# first, then strings, then everything else by its printed form.  Julia would
# refuse to compare these against each other otherwise.
function sort_key(value, fold_case::Bool)
    if value isa Bool
        return (3, 0.0, to_liquid_string(value))
    elseif value isa Number
        return (1, Float64(value), "")
    elseif value isa AbstractString
        return (2, 0.0, fold_case ? lowercase(value) : String(value))
    elseif value === nothing || value === missing
        return (4, 0.0, "")
    end
    return (3, 0.0, to_liquid_string(value))
end

function extractor(property)
    property === nothing && return identity
    key = to_liquid_string(property)
    return item -> _property_or_nil(item, key)
end

"""
    sort_filter(input, property = nothing)

`{{ list | sort }}`, comparing values by type and then by value.  With a
property name, entries are sorted by that property.

Values that are not scalars cannot be ordered against each other and are
rejected, which is what makes `{{ a | sort }}` an error for an array holding a
hash.
"""
function sort_filter(input, property = nothing)
    items = to_array(input)
    take = extractor(property)
    values = map(take, items)
    all(is_sortable, values) || filter_error("sort cannot order these values")
    return sort(items; by = item -> sort_key(take(item), false), alg = MergeSort)
end

is_sortable(::Union{Number,AbstractString,Nothing,Missing}) = true
is_sortable(::Any) = false

"""
    sort_natural(input, property = nothing)

`{{ list | sort_natural }}`, case-insensitive.

Unlike `sort`, this compares the *printed form* of each value, so numbers sort
as text: 1111 comes before 87, which comes before 9.  Nil sorts last.
"""
function sort_natural(input, property = nothing)
    take = extractor(property)
    return sort(to_array(input); alg = MergeSort, by = function (item)
        value = take(item)
        (value === nothing || value === missing) ? (1, "") :
            (0, lowercase(to_liquid_string(value)))
    end)
end

"""
    where_filter(input, property, target = nothing)

`{{ list | where: 'type', 'kitchen' }}`, the entries whose property equals
`target`.  With no target, the entries whose property is truthy.
"""
function where_filter(input, property, target = nothing)
    (input isa AbstractVector || input isa AbstractRange || input isa AbstractDict ||
     input isa Tuple || input === nothing || input === missing) ||
        filter_error("where needs an array, got $(type_name(input))")
    key = to_liquid_string(property)
    items = to_array(input)
    if target === nothing
        return filter(item -> is_truthy(_property_or_nil(item, key)), items)
    end
    return filter(item -> liquid_equal(_property_or_nil(item, key), target), items)
end
