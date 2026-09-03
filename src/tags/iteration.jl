# Looping tags.

"""
    parse_for(p::Parser, tok::Token) -> ForNode

Parse `{% for x in collection limit: n offset: m reversed %}`.

The modifiers may appear in any order, separated by whitespace or commas, which
is why they are read in a loop instead of positionally.
"""
function parse_for(p::Parser, tok::Token)
    args, line, col = tag_args(tok)
    isempty(args) && syntax_error(p, "for tag requires a loop variable", tok.line, tok.col)

    ep = ExprParser(tokenize_expression(args, line, col; template_name = p.template_name),
                    line, col, p.template_name)

    varname = expect!(ep, IDENT, "a loop variable")
    keyword = expect!(ep, IDENT, "'in'")
    keyword.value == "in" ||
        syntax_error(p, "expected 'in', got '$(keyword.value)'", keyword.line, keyword.col)

    # The collection as written is part of the loop's name, which
    # `{{ forloop.name }}` reports and `offset: continue` keys off.
    source_start = ep.pos
    iterable = parse_primary(ep)
    iterable_source = expression_source(ep, source_start)

    limit = nothing
    offset = nothing
    continue_offset = false
    reversed = false

    while (t = peek(ep)) !== nothing
        if t.kind === COMMA
            advance!(ep)
            continue
        end
        t.kind === IDENT ||
            syntax_error(p, "unexpected $(repr(t.value)) in for tag", t.line, t.col)
        advance!(ep)

        if t.value == "reversed"
            reversed = true
        elseif t.value == "limit" || t.value == "offset"
            expect!(ep, COLON, "':' after '$(t.value)'")
            # `offset: continue` is a keyword, not a value: it means "resume
            # where the last loop over this collection left off".
            if t.value == "offset" && (nt = peek(ep)) !== nothing &&
               nt.kind === IDENT && nt.value == "continue"
                advance!(ep)
                continue_offset = true
            elseif t.value == "limit"
                limit = parse_primary(ep)
            else
                offset = parse_primary(ep)
            end
        else
            syntax_error(p, "unknown for modifier '$(t.value)'", t.line, t.col)
        end
    end

    body, stop = parse_block!(p, ["else", "endfor"])
    else_body = Node[]
    if stop.name == "else"
        else_body, _ = parse_block!(p, ["endfor"])
    end
    return ForNode(varname.value, iterable, iterable_source, limit, offset,
                   continue_offset, reversed, body, else_body, tok.line)
end

"""
    parse_break(p::Parser, tok::Token) -> BreakNode

Parse `{% break %}`.  Whether it sits inside a loop is not checked here.
Outside a loop the interrupt travels all the way up and stops rendering the
rest of the template, which is what the reference implementation does; the
golden suite has no case for it.
"""
function parse_break(p::Parser, tok::Token)
    args, _, _ = tag_args(tok)
    isempty(args) || syntax_error(p, "break tag takes no arguments", tok.line, tok.col)
    return BreakNode(tok.line)
end

"""
    parse_continue(p::Parser, tok::Token) -> ContinueNode

Parse `{% continue %}`.
"""
function parse_continue(p::Parser, tok::Token)
    args, _, _ = tag_args(tok)
    isempty(args) || syntax_error(p, "continue tag takes no arguments", tok.line, tok.col)
    return ContinueNode(tok.line)
end

# Reconstruct the source text of the tokens consumed since `from`, used for the
# loop name: `{% for i in (1..3) %}` is named "i-(1..3)".
function expression_source(p::ExprParser, from::Int)
    io = IOBuffer()
    for i in from:(p.pos - 1)
        tok = p.tokens[i]
        print(io, tok.kind === STRING ? "'" * tok.value * "'" : tok.value)
    end
    return String(take!(io))
end
