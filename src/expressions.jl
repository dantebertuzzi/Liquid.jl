# Stage 2a: turn expression tokens into an expression AST.
#
# Liquid's expression grammar is small and, in one place, surprising: `and` and
# `or` share a single precedence level and associate to the *right*.  So
#
#     true and false and false or true
#
# means `true and (false and (false or true))`, which is false, and not the
# `(true and false and false) or true` that a Julia or Python reading would
# give.  `parse_boolean` below is where that rule lives.

"""
    Expression

Supertype of every node in an expression tree.  Expressions appear inside
`{{ ... }}` and as the operands of tags; they are evaluated against a context
at render time and never compiled to Julia code.
"""
abstract type Expression end

"""
    LiteralExpr(value)

A constant: a string, an integer, a float, `true`, `false`, `nothing` (Liquid's
`nil`), [`EMPTY`](@ref) or [`BLANK`](@ref).
"""
struct LiteralExpr <: Expression
    value::Any
end

"""
    VariableExpr(path, line, col)

A variable lookup such as `foo`, `foo.bar[0]` or `["key"]`.

`path` is the chain of lookups, root first, each an [`Expression`](@ref) that
evaluates to a key: `foo.bar` becomes `[LiteralExpr("foo"), LiteralExpr("bar")]`
and `a[b]` becomes `[LiteralExpr("a"), VariableExpr(...)]`.  Keeping the root in
the path makes `{{ ["foo"] }}`, a lookup with a computed root, fall out for
free instead of needing a special case.
"""
struct VariableExpr <: Expression
    path::Vector{Expression}
    line::Int
    col::Int
end

"""
    RangeExpr(start, stop)

A range literal, `(1..5)`.  Both ends are evaluated and truncated to integers
at render time, so `(1.4..5)` iterates from 1.
"""
struct RangeExpr <: Expression
    start::Expression
    stop::Expression
end

"""
    CompareOp

The binary operators usable in a condition.  `!=` and its alias `<>` both map
to `NE`.
"""
@enum CompareOp EQ NE GT LT GE LE CONTAINS

"""
    CompareExpr(op, left, right)

A comparison such as `a == b` or `a contains b`.  Liquid does not chain
comparisons, so the operands are always plain values.
"""
struct CompareExpr <: Expression
    op::CompareOp
    left::Expression
    right::Expression
    line::Int
    col::Int
end

CompareExpr(op::CompareOp, left::Expression, right::Expression) =
    CompareExpr(op, left, right, 0, 0)

"""
    BooleanExpr(op, left, right)

`left and right` or `left or right`.  `op` is `:and` or `:or`.  Both operators
share one precedence level and associate to the right.
"""
struct BooleanExpr <: Expression
    op::Symbol
    left::Expression
    right::Expression
end

"""
    NotExpr(operand)

Logical negation.  Liquid has no `not` operator; this node exists so that
`{% unless c %}` can be parsed into the same shape as `{% if %}` with its first
condition negated, instead of duplicating the whole conditional node.
"""
struct NotExpr <: Expression
    operand::Expression
end

"""
    FilterCall(name, args, kwargs, line, col)

One `| name: arg, key: value` step.  Positional and keyword arguments may be
interleaved in the source; they are separated here.
"""
struct FilterCall
    name::String
    args::Vector{Expression}
    kwargs::Vector{Pair{String,Expression}}
    line::Int
    col::Int
end

"""
    FilteredExpr(expr, filters)

An expression followed by a filter chain: what appears inside `{{ ... }}` and
on the right-hand side of `assign` and `echo`.  `filters` is empty when there
are none.
"""
struct FilteredExpr <: Expression
    expr::Expression
    filters::Vector{FilterCall}
end

# Structural equality, so tests can compare parsed trees against literals.
Base.:(==)(a::LiteralExpr, b::LiteralExpr) = a.value === b.value || a.value == b.value
Base.:(==)(a::VariableExpr, b::VariableExpr) = a.path == b.path
Base.:(==)(a::RangeExpr, b::RangeExpr) = a.start == b.start && a.stop == b.stop
Base.:(==)(a::CompareExpr, b::CompareExpr) = a.op == b.op && a.left == b.left && a.right == b.right
Base.:(==)(a::BooleanExpr, b::BooleanExpr) = a.op == b.op && a.left == b.left && a.right == b.right
Base.:(==)(a::NotExpr, b::NotExpr) = a.operand == b.operand
Base.:(==)(a::FilterCall, b::FilterCall) = a.name == b.name && a.args == b.args && a.kwargs == b.kwargs
Base.:(==)(a::FilteredExpr, b::FilteredExpr) = a.expr == b.expr && a.filters == b.filters

# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

# Cursor over the token vector.  Mutable because parsing is a walk with a
# position; every function below consumes from the front and never backtracks
# more than one token of lookahead.
mutable struct ExprParser
    tokens::Vector{ExprToken}
    pos::Int
    template_name::String
    line::Int   # fallback position, used when we run out of tokens
    col::Int
end

ExprParser(tokens, line, col, template_name) =
    ExprParser(tokens, 1, String(template_name), Int(line), Int(col))

peek(p::ExprParser, ahead::Int = 0) =
    p.pos + ahead <= length(p.tokens) ? p.tokens[p.pos+ahead] : nothing

function advance!(p::ExprParser)
    tok = peek(p)
    tok === nothing && _fail(p, "unexpected end of expression")
    p.pos += 1
    return tok
end

# Position to blame when the error is "something is missing at the end".
function _tail_position(p::ExprParser)
    isempty(p.tokens) && return p.line, p.col
    last = p.tokens[min(p.pos, length(p.tokens))]
    return last.line, last.col
end

function _fail(p::ExprParser, msg::AbstractString)
    line, col = _tail_position(p)
    throw(LiquidSyntaxError(msg, line, col; template_name = p.template_name))
end

function _fail(p::ExprParser, msg::AbstractString, tok::ExprToken)
    throw(LiquidSyntaxError(msg, tok.line, tok.col; template_name = p.template_name))
end

function expect!(p::ExprParser, kind::ExprTokenKind, what::AbstractString)
    tok = peek(p)
    (tok === nothing || tok.kind !== kind) && _fail(p, "expected $what")
    p.pos += 1
    return tok
end

# The words that are literals rather than variable names.
const KEYWORD_LITERALS = Dict{String,Any}(
    "true" => true, "false" => false,
    "nil" => nothing, "null" => nothing,
    "empty" => EMPTY, "blank" => BLANK,
)

const COMPARE_OPS = Dict{String,CompareOp}(
    "==" => EQ, "!=" => NE, "<>" => NE,
    ">" => GT, "<" => LT, ">=" => GE, "<=" => LE,
)

"""
    parse_primary(p::ExprParser) -> Expression

Parse a single value: a literal, a variable with its lookup path, or a range.
"""
function parse_primary(p::ExprParser)
    tok = peek(p)
    tok === nothing && _fail(p, "expected a value")

    if tok.kind === STRING
        advance!(p)
        return LiteralExpr(tok.value)
    elseif tok.kind === NUMBER
        advance!(p)
        return LiteralExpr(_parse_number(tok.value))
    elseif tok.kind === LPAREN
        return parse_range(p)
    elseif tok.kind === LBRACKET
        # A lookup whose root is written as a subscript: `{{ ["a b"] }}`.
        advance!(p)
        root = parse_primary(p)
        expect!(p, RBRACKET, "']'")
        return parse_path(p, root, tok.line, tok.col)
    elseif tok.kind === IDENT
        advance!(p)
        # A keyword is only a literal when nothing follows it.  With a path it
        # is an ordinary lookup of a variable that happens to share the name:
        # `{{ blank.a }}` with data `{"blank": {"a": 42}}` renders 42, and so
        # does `{% if nil.x.y == 42 %}` with a variable called "nil".
        if haskey(KEYWORD_LITERALS, tok.value) && !path_follows(p)
            return LiteralExpr(KEYWORD_LITERALS[tok.value])
        end
        return parse_path(p, LiteralExpr(tok.value), tok.line, tok.col)
    end
    _fail(p, "unexpected $(tok.kind) in expression", tok)
end

# Whether the next token starts a lookup path, `.name` or `[expr]`.
function path_follows(p::ExprParser)
    tok = peek(p)
    return tok !== nothing && (tok.kind === DOT || tok.kind === LBRACKET)
end

_parse_number(text::AbstractString) =
    occursin('.', text) ? parse(Float64, text) : parse(Int, text)

"""
    parse_range(p::ExprParser) -> RangeExpr

Parse `(start..stop)`.  Parentheses appear nowhere else in Liquid, so a `(`
always begins a range.
"""
function parse_range(p::ExprParser)
    expect!(p, LPAREN, "'('")
    start = parse_primary(p)
    expect!(p, DOTDOT, "'..' in range")
    stop = parse_primary(p)
    expect!(p, RPAREN, "')' to close range")
    return RangeExpr(start, stop)
end

"""
    parse_path(p::ExprParser, root, line, col) -> VariableExpr

Extend `root` with any `.name` and `[expr]` lookups that follow it.
"""
parse_path(p::ExprParser, root::Expression, line::Integer, col::Integer) =
    VariableExpr(Expression[root; collect_path!(p)], line, col)

"""
    collect_path!(p::ExprParser) -> Vector{Expression}

Read the `.name` and `[expr]` lookups that follow a value, if any.
"""
function collect_path!(p::ExprParser)
    path = Expression[]
    while true
        tok = peek(p)
        tok === nothing && break
        if tok.kind === DOT
            advance!(p)
            name = peek(p)
            (name === nothing || name.kind !== IDENT) && _fail(p, "expected a property name after '.'")
            advance!(p)
            push!(path, LiteralExpr(name.value))
        elseif tok.kind === LBRACKET
            advance!(p)
            push!(path, parse_primary(p))
            expect!(p, RBRACKET, "']'")
        else
            break
        end
    end
    return path
end

"""
    parse_comparison(p::ExprParser) -> Expression

Parse a value, optionally followed by one comparison operator and a second
value.  Liquid does not allow chained comparisons.
"""
function parse_comparison(p::ExprParser)
    left = parse_primary(p)
    tok = peek(p)
    tok === nothing && return left

    op = if tok.kind === OP
        get(COMPARE_OPS, tok.value, nothing)
    elseif tok.kind === IDENT && tok.value == "contains"
        CONTAINS
    else
        nothing
    end
    op === nothing && return left

    advance!(p)
    right = parse_primary(p)
    return CompareExpr(op, left, right, tok.line, tok.col)
end

"""
    parse_boolean(p::ExprParser) -> Expression

Parse a full condition.

`and` and `or` have equal precedence and associate to the right, so this
recurses into itself for the whole remainder rather than looping.  That single
choice is what makes `true and false and false or true` evaluate to false, the
way Liquid specifies and unlike every language that gives `and` the tighter
binding.
"""
function parse_boolean(p::ExprParser)
    left = parse_comparison(p)
    tok = peek(p)
    if tok !== nothing && tok.kind === IDENT && (tok.value == "and" || tok.value == "or")
        advance!(p)
        return BooleanExpr(Symbol(tok.value), left, parse_boolean(p))
    end
    return left
end

"""
    parse_filters!(p::ExprParser) -> Vector{FilterCall}

Parse a chain of `| name: arg, key: value` steps.
"""
function parse_filters!(p::ExprParser)
    filters = FilterCall[]
    while (tok = peek(p)) !== nothing && tok.kind === PIPE
        advance!(p)
        name = peek(p)
        (name === nothing || name.kind !== IDENT) && _fail(p, "expected a filter name after '|'")
        advance!(p)

        args = Expression[]
        kwargs = Pair{String,Expression}[]
        if (nxt = peek(p)) !== nothing && nxt.kind === COLON
            advance!(p)
            while true
                _parse_filter_argument!(p, args, kwargs)
                (more = peek(p)) !== nothing && more.kind === COMMA || break
                advance!(p)
            end
        end
        push!(filters, FilterCall(name.value, args, kwargs, name.line, name.col))
    end
    return filters
end

# A keyword argument is an identifier followed by a colon.  Anything else is
# positional.  The two may be interleaved: `default: allow_false: false, "bar"`
# occurs in the reference test suite.
function _parse_filter_argument!(p::ExprParser, args, kwargs)
    tok = peek(p)
    nxt = peek(p, 1)
    if tok !== nothing && tok.kind === IDENT && nxt !== nothing && nxt.kind === COLON
        advance!(p)
        advance!(p)
        push!(kwargs, tok.value => parse_primary(p))
    else
        push!(args, parse_primary(p))
    end
    return nothing
end

# Every entry point below parses a whole string and insists that nothing is
# left over, so trailing junk is a syntax error instead of being ignored.
function _finish(p::ExprParser, expr)
    tok = peek(p)
    tok === nothing || _fail(p, "unexpected $(repr(tok.value)) after expression", tok)
    return expr
end

_parser(src, line, col, template_name) =
    ExprParser(tokenize_expression(src, line, col; template_name), line, col, template_name)

"""
    parse_value(src, line, col; template_name = "") -> Expression

Parse a single value with no filters and no comparison, such as the operand of
`{% increment %}` or the right-hand side of a `for ... in`.
"""
function parse_value(src::AbstractString, line::Integer, col::Integer;
                     template_name::AbstractString = "")
    p = _parser(src, line, col, template_name)
    return _finish(p, parse_primary(p))
end

"""
    parse_condition(src, line, col; template_name = "") -> Expression

Parse the condition of `{% if %}`, `{% elsif %}` or `{% unless %}`.
"""
function parse_condition(src::AbstractString, line::Integer, col::Integer;
                         template_name::AbstractString = "")
    p = _parser(src, line, col, template_name)
    isempty(p.tokens) && throw(LiquidSyntaxError("empty condition", line, col; template_name))
    return _finish(p, parse_boolean(p))
end

"""
    parse_filtered(src, line, col; template_name = "") -> FilteredExpr

Parse an expression with an optional filter chain: the content of `{{ ... }}`,
of `{% echo %}`, and of the right-hand side of `{% assign %}`.
"""
function parse_filtered(src::AbstractString, line::Integer, col::Integer;
                        template_name::AbstractString = "")
    p = _parser(src, line, col, template_name)
    isempty(p.tokens) && throw(LiquidSyntaxError("empty expression", line, col; template_name))
    expr = parse_primary(p)
    return _finish(p, FilteredExpr(expr, parse_filters!(p)))
end
