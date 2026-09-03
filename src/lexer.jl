# Stage 1: split raw template source into a flat sequence of tokens.
#
# This lexer only knows about the three things that can appear at the top level
# of a template: literal text, an output statement `{{ ... }}` and a tag
# `{% ... %}`.  It does not look inside the delimiters beyond picking off the
# tag name; tokenizing an expression is the expression lexer's job.

"""
    TokenKind

What a [`Token`](@ref) represents: literal `TEXT`, an `OUTPUT` statement
(`{{ ... }}`) or a `TAG` (`{% ... %}`).
"""
@enum TokenKind TEXT OUTPUT TAG

"""
    Token

One top-level template token.

- `kind`: see [`TokenKind`](@ref).
- `value`: for `TEXT`, the literal text; for `OUTPUT` and `TAG`, the whole
  content between the delimiters with surrounding whitespace stripped.
- `name`: for `TAG`, the tag name (`"if"`, `"endfor"`); empty otherwise.
- `trim_left`, `trim_right`: whether the token was written with `-` on that
  side of its delimiter, e.g. `{{- x -}}`.  These say what should happen to the
  *neighbouring* text, and are consumed by [`apply_whitespace_control`](@ref).
- `line`, `col`: 1-based position of `value` in the source.

`line` and `col` point at the first character of `value`, not at the opening
delimiter, so an error reported against a token points at its content.
"""
struct Token
    kind::TokenKind
    value::String
    name::String
    trim_left::Bool
    trim_right::Bool
    line::Int
    col::Int
end

Base.:(==)(a::Token, b::Token) =
    a.kind == b.kind && a.value == b.value && a.name == b.name &&
    a.trim_left == b.trim_left && a.trim_right == b.trim_right &&
    a.line == b.line && a.col == b.col

function Base.show(io::IO, tok::Token)
    print(io, "Token(", tok.kind)
    tok.kind === TAG && print(io, " ", repr(tok.name))
    print(io, ", ", repr(tok.value), ", ", tok.line, ":", tok.col)
    tok.trim_left && print(io, ", trim_left")
    tok.trim_right && print(io, ", trim_right")
    print(io, ")")
end

# `{% raw %}` is handled here rather than in the parser because its body must
# never be tokenized: it is allowed to contain unbalanced `{{` and `{%`.
const RAW_END = r"\{%(-?)\s*endraw\s*(-?)%\}"

"""
    tokenize(source; template_name = "") -> Vector{Token}

Split raw template `source` into text, output and tag tokens.

Whitespace control markers are recorded on the tokens but not yet applied; run
[`apply_whitespace_control`](@ref) on the result for that.  The body of a
`{% raw %}` block is returned as a single `TEXT` token.

Throws [`LiquidSyntaxError`](@ref) for an unclosed delimiter, an unterminated
string literal inside a delimiter, or a `{% raw %}` with no `{% endraw %}`.
"""
function tokenize(source::AbstractString; template_name::AbstractString = "")
    src = String(source)
    tokens = Token[]
    starts = _line_starts(src)
    stop = lastindex(src)

    text_start = firstindex(src)  # start of the literal run we have not emitted yet
    pos = firstindex(src)

    while pos <= stop
        open = findnext('{', src, pos)
        open === nothing && break
        after = nextind(src, open)
        if after > stop
            break
        end
        marker = src[after]
        if marker !== '{' && marker !== '%'
            pos = after  # a lone `{`, keep it as text and move on
            continue
        end

        # Everything before the delimiter is literal text.
        if open > text_start
            push!(tokens, _text_token(src, starts, text_start, prevind(src, open)))
        end

        kind = marker === '{' ? OUTPUT : TAG
        close_first, close_last = marker === '{' ? ('}', '}') : ('%', '}')

        inner_start = nextind(src, after)
        trim_left = inner_start <= stop && src[inner_start] === '-'
        trim_left && (inner_start = nextind(src, inner_start))

        close_range = _find_closer(src, close_first, close_last, inner_start,
                                   starts, open, kind, template_name)
        inner_stop = prevind(src, first(close_range))
        trim_right = inner_stop >= inner_start && src[inner_stop] === '-'
        trim_right && (inner_stop = prevind(src, inner_stop))

        value, line, col = _strip_inner(src, starts, inner_start, inner_stop)
        name = kind === TAG ? _tag_name(value) : ""

        if kind === TAG && name == "raw"
            pos = text_start = _lex_raw!(tokens, src, starts, value, trim_left,
                                         trim_right, line, col,
                                         nextind(src, last(close_range)), template_name)
        else
            push!(tokens, Token(kind, value, name, trim_left, trim_right, line, col))
            pos = text_start = nextind(src, last(close_range))
        end
    end

    if text_start <= stop
        push!(tokens, _text_token(src, starts, text_start, stop))
    end
    return tokens
end

# Consume a `{% raw %}` body and push it as a single TEXT token.  Returns the
# index just past `{% endraw %}`.
function _lex_raw!(tokens, src, starts, value, open_trim_left, open_trim_right,
                   line, col, body_start, template_name)
    if length(value) != 3  # value is the whole tag body, which must be just "raw"
        throw(LiquidSyntaxError("raw tag takes no arguments", line, col;
                                template_name))
    end

    m = match(RAW_END, src, body_start)
    m === nothing &&
        throw(LiquidSyntaxError("raw tag was never closed", line, col; template_name))

    body = body_start > m.offset ? "" : String(SubString(src, body_start, prevind(src, m.offset)))
    # The inner markers of `{% raw -%}` and `{%- endraw %}` trim the raw body
    # itself; the outer ones trim the neighbouring text and travel on the token.
    open_trim_right && (body = lstrip(body))
    m.captures[1] == "-" && (body = rstrip(body))

    bline, bcol = _line_col(src, starts, min(body_start, lastindex(src)))
    push!(tokens, Token(TEXT, String(body), "", open_trim_left,
                        m.captures[2] == "-", bline, bcol))
    return m.offset + ncodeunits(m.match)
end

function _text_token(src, starts, from, to)
    line, col = _line_col(src, starts, from)
    Token(TEXT, String(SubString(src, from, to)), "", false, false, line, col)
end

# Scan forward for the closing delimiter, skipping over string literals so that
# `{{ "}}" }}` closes at the right place.  Liquid strings have no escapes.
function _find_closer(src, c1, c2, from, starts, open_at, kind, template_name)
    i = from
    stop = lastindex(src)
    while i <= stop
        c = src[i]
        if c === '\'' || c === '"'
            j = findnext(c, src, nextind(src, i))
            if j === nothing
                line, col = _line_col(src, starts, i)
                throw(LiquidSyntaxError("unterminated string literal", line, col;
                                        template_name))
            end
            i = nextind(src, j)
        elseif c === c1
            j = nextind(src, i)
            if j <= stop && src[j] === c2
                return i:j
            end
            i = j
        else
            i = nextind(src, i)
        end
    end
    line, col = _line_col(src, starts, open_at)
    what = kind === OUTPUT ? "output statement" : "tag"
    throw(LiquidSyntaxError("unclosed $what", line, col; template_name))
end

# Strip whitespace off both ends of the delimiter body and report where the
# remaining content actually starts.
function _strip_inner(src, starts, from, to)
    i, j = from, to
    while i <= j && isspace(src[i])
        i = nextind(src, i)
    end
    while j >= i && isspace(src[j])
        j = prevind(src, j)
    end
    if i > j
        line, col = _line_col(src, starts, min(from, lastindex(src)))
        return "", line, col
    end
    line, col = _line_col(src, starts, i)
    return String(SubString(src, i, j)), line, col
end

# The tag name is the leading identifier of the tag body.  A body that does not
# start with one yields "", and the parser turns that into "unknown tag".
function _tag_name(value::AbstractString)
    m = match(r"^[a-zA-Z_][a-zA-Z_0-9]*", value)
    m === nothing ? "" : String(m.match)
end

"""
    tag_args(tok::Token) -> (args, line, col)

The arguments of a tag token: everything after the tag name, with its own
position so that errors inside the arguments are reported accurately.
"""
function tag_args(tok::Token)
    rest = SubString(tok.value, nextind(tok.value, 0, length(tok.name) + 1))
    stripped = lstrip(rest)
    # The tag name cannot contain a newline, so the arguments stay on tok.line.
    col = tok.col + length(tok.name) + (length(rest) - length(stripped))
    return String(rstrip(stripped)), tok.line, col
end

"""
    apply_whitespace_control(tokens) -> Vector{Token}

Apply the `-` whitespace markers recorded on `tokens` and drop the text tokens
that become empty.

A `trim_left` marker strips trailing whitespace from the preceding text token,
`trim_right` strips leading whitespace from the following one.  Liquid removes
*all* adjacent whitespace, newlines included, not just up to a line boundary.
"""
function apply_whitespace_control(tokens::Vector{Token})
    out = copy(tokens)
    for (i, tok) in enumerate(tokens)
        if tok.trim_left && i > 1 && out[i-1].kind === TEXT
            out[i-1] = _retext(out[i-1], rstrip(out[i-1].value))
        end
        if tok.trim_right && i < length(out) && out[i+1].kind === TEXT
            out[i+1] = _retext(out[i+1], lstrip(out[i+1].value))
        end
    end
    return filter(t -> !(t.kind === TEXT && isempty(t.value)), out)
end

_retext(tok::Token, text::AbstractString) =
    Token(tok.kind, String(text), tok.name, tok.trim_left, tok.trim_right, tok.line, tok.col)

# Byte index of the first character of each line, so positions can be recovered
# with a binary search instead of counting newlines token by token.
function _line_starts(src::AbstractString)
    starts = [firstindex(src)]
    for (i, c) in pairs(src)
        c === '\n' && push!(starts, nextind(src, i))
    end
    return starts
end

function _line_col(src::AbstractString, starts::Vector{Int}, idx::Integer)
    line = searchsortedlast(starts, idx)
    line == 0 && return 1, 1
    return line, length(src, starts[line], idx)
end
