# Stage 1b: tokenize the inside of a `{{ ... }}` or `{% ... %}` delimiter.
#
# This lexer stays deliberately dumb: it classifies characters and nothing
# else.  Words like `and`, `or`, `contains`, `true` and `nil` come out as
# ordinary identifiers, because whether a word is a keyword depends on where it
# sits in the grammar, which only the parser knows.  That also means a template
# is free to have a variable named `contains`.

"""
    ExprTokenKind

Lexical class of an [`ExprToken`](@ref).

`IDENT` covers keywords too (`and`, `true`, `nil`); the parser decides what
they mean.  `OP` covers the comparison operators written with symbols.
"""
@enum ExprTokenKind IDENT STRING NUMBER OP DOT DOTDOT LBRACKET RBRACKET LPAREN RPAREN PIPE COLON COMMA

"""
    ExprToken

One token from inside a delimiter.  `value` holds the text, except for
`STRING`, where the surrounding quotes are removed.  `line` and `col` are
absolute positions in the original template.
"""
struct ExprToken
    kind::ExprTokenKind
    value::String
    line::Int
    col::Int
end

Base.:(==)(a::ExprToken, b::ExprToken) =
    a.kind == b.kind && a.value == b.value && a.line == b.line && a.col == b.col

Base.show(io::IO, t::ExprToken) =
    print(io, "ExprToken(", t.kind, ", ", repr(t.value), ", ", t.line, ":", t.col, ")")

# Identifiers may contain hyphens: `{% assign some-thing = 1 %}` is valid
# Liquid.  Since Liquid has no arithmetic, a `-` is never an operator, so this
# is unambiguous: a `-` starts a number only when it starts a token.  A
# trailing `?` is also allowed, inherited from Ruby: `{{ bar? }}` is a lookup
# of the key "bar?".
const RE_IDENT = r"^[a-zA-Z_][a-zA-Z_0-9-]*\??"
# `\.\d+` requires a digit after the dot, so `1..5` lexes as `1`, `..`, `5`
# and `1.4..5` as `1.4`, `..`, `5`.
const RE_NUMBER = r"^-?[0-9]+(\.[0-9]+)?"

# Two-character tokens must be tried before their one-character prefixes.
const OPS2 = ("==", "!=", "<>", ">=", "<=")

"""
    tokenize_expression(src, line, col; template_name = "") -> Vector{ExprToken}

Tokenize `src`, the content of a delimiter, which starts at absolute position
(`line`, `col`) in the template.  Positions on the returned tokens are absolute,
so errors can be reported against the original source.

Throws [`LiquidSyntaxError`](@ref) on an unterminated string or a character
that cannot start a token.
"""
function tokenize_expression(src::AbstractString, line::Integer, col::Integer;
                             template_name::AbstractString = "")
    s = String(src)
    tokens = ExprToken[]
    starts = _line_starts(s)
    stop = lastindex(s)
    i = firstindex(s)

    # Absolute position of the character at byte index `idx`.
    at(idx) = _absolute(line, col, _line_col(s, starts, idx)...)

    while i <= stop
        c = s[i]

        if isspace(c)
            i = nextind(s, i)
            continue
        end

        tline, tcol = at(i)

        if c === '\'' || c === '"'
            j = findnext(c, s, nextind(s, i))
            if j === nothing
                throw(LiquidSyntaxError("unterminated string literal", tline, tcol;
                                        template_name))
            end
            body = nextind(s, i) > prevind(s, j) ? "" : String(SubString(s, nextind(s, i), prevind(s, j)))
            push!(tokens, ExprToken(STRING, body, tline, tcol))
            i = nextind(s, j)
            continue
        end

        rest = SubString(s, i)

        if isdigit(c) || (c === '-' && _digit_follows(s, i))
            m = match(RE_NUMBER, rest)
            push!(tokens, ExprToken(NUMBER, String(m.match), tline, tcol))
            i += ncodeunits(m.match)
            continue
        end

        if (isascii(c) && isletter(c)) || c === '_'
            m = match(RE_IDENT, rest)
            push!(tokens, ExprToken(IDENT, String(m.match), tline, tcol))
            i += ncodeunits(m.match)
            continue
        end

        j = nextind(s, i)
        two = j <= stop ? String(SubString(s, i, j)) : ""
        if two in OPS2
            push!(tokens, ExprToken(OP, two, tline, tcol))
            i += 2
            continue
        end
        if two == ".."
            push!(tokens, ExprToken(DOTDOT, "..", tline, tcol))
            i += 2
            continue
        end

        kind = c === '.' ? DOT :
               c === '[' ? LBRACKET :
               c === ']' ? RBRACKET :
               c === '(' ? LPAREN :
               c === ')' ? RPAREN :
               c === '|' ? PIPE :
               c === ':' ? COLON :
               c === ',' ? COMMA :
               (c === '>' || c === '<') ? OP : nothing

        if kind === nothing
            throw(LiquidSyntaxError("unexpected character $(repr(c))", tline, tcol;
                                    template_name))
        end
        push!(tokens, ExprToken(kind, string(c), tline, tcol))
        i = nextind(s, i)
    end

    return tokens
end

_digit_follows(s, i) = (j = nextind(s, i); j <= lastindex(s) && isdigit(s[j]))

# Translate a position relative to the delimiter body into a template position.
# Only the first line is offset by the body's starting column.
_absolute(base_line, base_col, rel_line, rel_col) =
    rel_line == 1 ? (base_line, base_col + rel_col - 1) : (base_line + rel_line - 1, rel_col)
