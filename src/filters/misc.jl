# Filters that are neither numeric, string nor array work: defaults, escaping,
# and URL encoding.

"""
    default_filter(input, fallback = nothing; allow_false = false)

`{{ x | default: "none" }}`.

The fallback is used when the input is blank: nil, `false`, an empty string, an
empty array or an empty hash.  Zero is *not* blank, so `{{ 0 | default: 5 }}`
is 0.  Pass `allow_false: true` to let an explicit `false` through.
"""
function default_filter(input, fallback = nothing; allow_false = false)
    is_truthy(allow_false) && input === false && return input
    return is_blank(input) ? fallback : input
end

"""
    escape_filter(input)

`{{ "<b>" | escape }}`, HTML-escaping the five significant characters.
"""
escape_filter(input) = escape_html(to_liquid_string(input))

# An entity that is already escaped: a named one, or a numeric one.
const HTML_ENTITY = r"&(?:[a-zA-Z][a-zA-Z0-9]*|#[0-9]+|#[xX][0-9a-fA-F]+);"

"""
    escape_once(input)

`{{ "&lt;p&gt;<b>" | escape_once }}`, escaping without double-escaping what is
already an entity.
"""
function escape_once(input)
    text = to_liquid_string(input)
    out = IOBuffer()
    position = firstindex(text)
    # Copy existing entities through untouched and escape everything between.
    for m in eachmatch(HTML_ENTITY, text)
        print(out, escape_html(SubString(text, position, prevind(text, m.offset))))
        print(out, m.match)
        position = m.offset + ncodeunits(m.match)
    end
    print(out, escape_html(SubString(text, position)))
    return String(take!(out))
end

# Ruby's CGI.escape leaves these alone and turns a space into "+".
is_url_safe(c::Char) = isascii(c) && (isletter(c) || isdigit(c) || c in ('_', '.', '-'))

"""
    url_encode(input)

`{{ "a b@c" | url_encode }}`.  Spaces become `+` and everything outside
`[A-Za-z0-9_.-]` is percent-encoded, matching Ruby's `CGI.escape`.
"""
function url_encode(input)
    out = IOBuffer()
    for byte in codeunits(to_liquid_string(input))
        c = Char(byte)
        if is_url_safe(c)
            print(out, c)
        elseif c == ' '
            print(out, '+')
        else
            print(out, '%', uppercase(string(byte; base = 16, pad = 2)))
        end
    end
    return String(take!(out))
end

"""
    url_decode(input)

`{{ "a+b%40c" | url_decode }}`, the inverse of [`url_encode`](@ref).
"""
function url_decode(input)
    text = to_liquid_string(input)
    bytes = UInt8[]
    i = firstindex(text)
    stop = lastindex(text)
    while i <= stop
        c = text[i]
        if c == '%' && i + 2 <= stop
            hex = SubString(text, i + 1, i + 2)
            parsed = tryparse(UInt8, hex; base = 16)
            if parsed !== nothing
                push!(bytes, parsed)
                i += 3
                continue
            end
        end
        if c == '+'
            push!(bytes, UInt8(' '))
        else
            append!(bytes, codeunits(string(c)))
        end
        i = nextind(text, i)
    end
    return String(bytes)
end
