# Tags that bind or emit values.

# Liquid is generous about what a *binding* name may contain: `{% assign
# foo-a = 1 %}`, `{% assign 123 = 1 %}` and `{% capture _ %}` are all valid, and
# a key that is not a plain identifier is read back with `{{ ["123"] }}`.
#
# Two shapes are rejected: a leading hyphen, and a trailing `?`.  The `?` is
# allowed when *reading* (`{{ bar? }}` looks up the key "bar?") but not when
# binding, which is the asymmetry the reference suite encodes.
is_valid_binding_name(name::AbstractString) =
    !isempty(name) && !startswith(name, '-') && !any(isspace, name) &&
    !occursin('?', name)

"""
    parse_assign(p::Parser, tok::Token) -> AssignNode

Parse `{% assign name = value | filters %}`.

The name is taken from the raw text up to the first `=` rather than from the
expression lexer, because a binding name may be something the expression
grammar would not accept, such as `123`.
"""
function parse_assign(p::Parser, tok::Token)
    args, line, col = tag_args(tok)
    equals = findfirst('=', args)
    equals === nothing &&
        syntax_error(p, "assign tag requires '=' ", tok.line, tok.col)

    name = strip(args[1:prevind(args, equals)])
    is_valid_binding_name(name) ||
        syntax_error(p, "invalid assignment name $(repr(String(name)))", line, col)

    rhs_start = nextind(args, equals)
    rhs = rhs_start > lastindex(args) ? "" : args[rhs_start:end]
    isempty(strip(rhs)) &&
        syntax_error(p, "assign tag requires a value", line, col)

    # Column of the right-hand side, so an error in it points at the right spot.
    rhs_col = col + length(args[1:equals])
    expr = parse_filtered(strip(rhs), line, rhs_col + (length(rhs) - length(lstrip(rhs)));
                          template_name = p.template_name)
    return AssignNode(String(name), expr, tok.line)
end

"""
    parse_capture(p::Parser, tok::Token) -> CaptureNode

Parse `{% capture name %} ... {% endcapture %}`.
"""
function parse_capture(p::Parser, tok::Token)
    name, line, col = tag_args(tok)
    is_valid_binding_name(name) ||
        syntax_error(p, "invalid capture name $(repr(name))", line, col)
    body, _ = parse_block!(p, ["endcapture"])
    return CaptureNode(name, body, tok.line)
end

"""
    parse_echo(p::Parser, tok::Token) -> EchoNode

Parse `{% echo value | filters %}`.  An empty `{% echo %}` is valid and renders
nothing, unlike an empty `{{ }}`.
"""
function parse_echo(p::Parser, tok::Token)
    args, line, col = tag_args(tok)
    isempty(args) &&
        return EchoNode(FilteredExpr(LiteralExpr(nothing), FilterCall[]), tok.line)
    expr = parse_filtered(args, line, col; template_name = p.template_name)
    return EchoNode(expr, tok.line)
end

"""
    parse_increment(p::Parser, tok::Token) -> IncrementNode

Parse `{% increment name %}`.
"""
function parse_increment(p::Parser, tok::Token)
    name, line, col = tag_args(tok)
    is_valid_binding_name(name) ||
        syntax_error(p, "increment tag requires a name", line, col)
    return IncrementNode(name, tok.line)
end

"""
    parse_decrement(p::Parser, tok::Token) -> DecrementNode

Parse `{% decrement name %}`.
"""
function parse_decrement(p::Parser, tok::Token)
    name, line, col = tag_args(tok)
    is_valid_binding_name(name) ||
        syntax_error(p, "decrement tag requires a name", line, col)
    return DecrementNode(name, tok.line)
end
