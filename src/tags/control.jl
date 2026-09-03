# Conditional tags.

"""
    parse_if(p::Parser, tok::Token) -> IfNode

Parse `{% if %} ... {% elsif %} ... {% else %} ... {% endif %}`.

The arms are collected into a flat list of [`ConditionalBranch`](@ref)es rather
than nested nodes, so the renderer is a single loop over them.

Arms that follow the first `{% else %}` are still parsed, so a syntax error
there is still reported, but their bodies are dropped: Shopify renders
`{% if false %}1{% else %}2{% else %}3{% endif %}` as `"2"`.
"""
function parse_if(p::Parser, tok::Token)
    args, line, col = tag_args(tok)
    isempty(args) && syntax_error(p, "if tag requires a condition", tok.line, tok.col)

    branches = ConditionalBranch[]
    else_body = Node[]
    seen_else = false
    # The guard for the block we are about to read; `nothing` means that block
    # is an else body rather than a conditional branch.
    condition = parse_condition(args, line, col; template_name = p.template_name)

    while true
        body, stop = parse_block!(p, ["elsif", "else", "endif"])

        if condition !== nothing
            push!(branches, ConditionalBranch(condition, body))
        elseif !seen_else
            else_body = body
            seen_else = true
        end

        stop.name == "endif" && return IfNode(branches, else_body, tok.line)

        if stop.name == "elsif"
            eargs, eline, ecol = tag_args(stop)
            isempty(eargs) &&
                syntax_error(p, "elsif tag requires a condition", stop.line, stop.col)
            elsif_condition = parse_condition(eargs, eline, ecol;
                                              template_name = p.template_name)
            condition = seen_else ? nothing : elsif_condition
        else
            condition = nothing
        end
    end
end

"""
    parse_unless(p::Parser, tok::Token) -> IfNode

Parse `{% unless %} ... {% elsif %} ... {% else %} ... {% endunless %}`.

Only the first condition is negated; `elsif` arms are tested as written, which
is why `{% unless true %}foo{% elsif true %}bar{% endunless %}` renders "bar".
The result is an ordinary [`IfNode`](@ref), so the renderer has one shape of
conditional to handle rather than two.
"""
function parse_unless(p::Parser, tok::Token)
    args, line, col = tag_args(tok)
    isempty(args) && syntax_error(p, "unless tag requires a condition", tok.line, tok.col)

    branches = ConditionalBranch[]
    else_body = Node[]
    seen_else = false
    condition = NotExpr(parse_condition(args, line, col; template_name = p.template_name))

    while true
        body, stop = parse_block!(p, ["elsif", "else", "endunless"])

        if condition !== nothing
            push!(branches, ConditionalBranch(condition, body))
        elseif !seen_else
            else_body = body
            seen_else = true
        end

        stop.name == "endunless" && return IfNode(branches, else_body, tok.line)

        if stop.name == "elsif"
            eargs, eline, ecol = tag_args(stop)
            isempty(eargs) &&
                syntax_error(p, "elsif tag requires a condition", stop.line, stop.col)
            elsif_condition = parse_condition(eargs, eline, ecol;
                                              template_name = p.template_name)
            condition = seen_else ? nothing : elsif_condition
        else
            condition = nothing
        end
    end
end

"""
    parse_case(p::Parser, tok::Token) -> CaseNode

Parse `{% case %} ... {% when %} ... {% else %} ... {% endcase %}`.

Text between `{% case %}` and the first `{% when %}` is discarded, and the arms
are kept in source order because every matching `when` renders, not just the
first.  A `when` may list several values separated by commas or by `or`.
"""
function parse_case(p::Parser, tok::Token)
    args, line, col = tag_args(tok)
    isempty(args) && syntax_error(p, "case tag requires a value", tok.line, tok.col)
    subject = parse_value(args, line, col; template_name = p.template_name)

    # Whatever sits before the first arm is not rendered.
    _, stop = parse_block!(p, ["when", "else", "endcase"])
    branches = CaseBranch[]

    while stop.name != "endcase"
        if stop.name == "when"
            wargs, wline, wcol = tag_args(stop)
            isempty(wargs) &&
                syntax_error(p, "when tag requires a value", stop.line, stop.col)
            values = parse_when_values(p, wargs, wline, wcol)
            body, stop = parse_block!(p, ["when", "else", "endcase"])
            push!(branches, CaseBranch(values, body))
        else
            body, stop = parse_block!(p, ["when", "else", "endcase"])
            push!(branches, CaseBranch(nothing, body))
        end
    end
    return CaseNode(subject, branches, tok.line)
end

# `{% when 'a', 'b' %}` and `{% when 'a' or 'b' %}` mean the same thing, and may
# be mixed: `{% when 'bar' or 'Hello', 'Hello' %}` lists three values.
function parse_when_values(p::Parser, src::AbstractString, line::Integer, col::Integer)
    ep = ExprParser(tokenize_expression(src, line, col; template_name = p.template_name),
                    line, col, p.template_name)
    values = Expression[parse_primary(ep)]
    while (tok = peek(ep)) !== nothing
        if tok.kind === COMMA || (tok.kind === IDENT && tok.value == "or")
            advance!(ep)
            push!(values, parse_primary(ep))
        else
            syntax_error(p, "expected ',' or 'or' in when tag", tok.line, tok.col)
        end
    end
    return values
end
