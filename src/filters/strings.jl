# String filters.
#
# Every one of these coerces its input with `to_liquid_string`, so a number or
# nil goes through unharmed: `{{ 5 | upcase }}` is "5" and `{{ nope | strip }}`
# is "".  Filters whose name would shadow a Base function carry a `_filter`
# suffix; the name a template uses is set in `default_filters`.

"""
    append(input, suffix)

`{{ "hello" | append: "there" }}`.
"""
append(input, suffix) = to_liquid_string(input) * to_liquid_string(suffix)

"""
    prepend(input, prefix)

`{{ "hello" | prepend: "there" }}`.
"""
prepend(input, prefix) = to_liquid_string(prefix) * to_liquid_string(input)

"""
    capitalize(input)

`{{ "hello world" | capitalize }}` is "Hello world": the first character is
upper-cased and the rest lower-cased, as in Ruby.
"""
function capitalize(input)
    text = to_liquid_string(input)
    isempty(text) && return text
    return uppercase(text[1:1]) * lowercase(text[nextind(text, 1):end])
end

"""
    downcase(input)

`{{ "HELLO" | downcase }}`.
"""
downcase(input) = lowercase(to_liquid_string(input))

"""
    upcase(input)

`{{ "hello" | upcase }}`.
"""
upcase(input) = uppercase(to_liquid_string(input))

"""
    strip_filter(input)

`{{ " hi " | strip }}`, whitespace removed from both ends.
"""
strip_filter(input) = strip(to_liquid_string(input))

"""
    lstrip_filter(input)

`{{ " hi " | lstrip }}`, whitespace removed from the start.
"""
lstrip_filter(input) = lstrip(to_liquid_string(input))

"""
    rstrip_filter(input)

`{{ " hi " | rstrip }}`, whitespace removed from the end.
"""
rstrip_filter(input) = rstrip(to_liquid_string(input))

"""
    strip_newlines(input)

`{{ "a\\nb" | strip_newlines }}`, newlines removed outright rather than
replaced by spaces.
"""
strip_newlines(input) = replace(to_liquid_string(input), r"\r?\n" => "")

"""
    newline_to_br(input)

`{{ "a\\nb" | newline_to_br }}`.  The newline is kept as well as the `<br />`.
"""
newline_to_br(input) = replace(to_liquid_string(input), r"\r?\n" => "<br />\n")

# `<script>` and `<style>` lose their contents, not just their tags, and
# comments go entirely.  Entities are left alone: `&amp;` stays `&amp;`.
const HTML_COMMENT = r"<!--.*?-->"s
const HTML_SCRIPT = r"<script.*?</script>"is
const HTML_STYLE = r"<style.*?</style>"is
const HTML_TAG = r"<.*?>"s

"""
    strip_html(input)

`{{ "<b>hi</b>" | strip_html }}`.

Removes tags, HTML comments, and the *contents* of `<script>` and `<style>`
elements.  Entities are not decoded.
"""
function strip_html(input)
    text = to_liquid_string(input)
    text = replace(text, HTML_COMMENT => "")
    text = replace(text, HTML_SCRIPT => "")
    text = replace(text, HTML_STYLE => "")
    return replace(text, HTML_TAG => "")
end

"""
    remove(input, needle)

`{{ "a-b-c" | remove: "-" }}`, every occurrence.
"""
remove(input, needle) = replace_filter(input, needle, "")

"""
    remove_first(input, needle)

`{{ "a-b-c" | remove_first: "-" }}`, the first occurrence only.
"""
remove_first(input, needle) = replace_first(input, needle, "")

"""
    replace_filter(input, needle, replacement = "")

`{{ "a-b" | replace: "-", "+" }}`, every occurrence.

With one argument the replacement is empty. Note that replacing the empty
string inserts between every character, which is what makes
`{{ "ab" | replace: nil, "#" }}` render "#a#b#".
"""
replace_filter(input, needle, replacement = "") =
    replace(to_liquid_string(input), to_liquid_string(needle) => to_liquid_string(replacement))

"""
    replace_first(input, needle, replacement = "")

`{{ "a-b-c" | replace_first: "-", "+" }}`, the first occurrence only.
"""
replace_first(input, needle, replacement = "") =
    replace(to_liquid_string(input), to_liquid_string(needle) => to_liquid_string(replacement); count = 1)

# `truncate` and `truncatewords` need a real number; unlike most filters they
# do not fall back to zero.
function required_count(argument, name::AbstractString)
    value = to_number(argument)
    value === nothing && filter_error("$name needs a number, got $(type_name(argument))")
    return trunc(Int, value)
end

"""
    truncate_filter(input, length = 50, ellipsis = "...")

`{{ text | truncate: 20 }}`.

`length` counts the ellipsis, so the result is never longer than asked: with
the default ellipsis, `truncate: 20` keeps 17 characters and appends "...".
"""
function truncate_filter(input, length_ = 50, ellipsis = "...")
    text = to_liquid_string(input)
    limit = required_count(length_, "truncate")
    tail = to_liquid_string(ellipsis)

    length(text) <= limit && return text
    keep = limit - length(tail)
    keep <= 0 && return first(tail, limit)
    return first(text, keep) * tail
end

"""
    truncatewords(input, count = 15, ellipsis = "...")

`{{ text | truncatewords: 3 }}`.

Words are split on any run of whitespace and rejoined with single spaces. A
count below 1 is treated as 1, so `truncatewords: 0` still keeps one word.
"""
function truncatewords(input, count = 15, ellipsis = "...")
    text = to_liquid_string(input)
    limit = max(required_count(count, "truncatewords"), 1)
    tail = to_liquid_string(ellipsis)

    words = split(text)
    length(words) <= limit && return join(words, " ")
    return join(view(words, 1:limit), " ") * tail
end
