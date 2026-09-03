# Tags that are neither control flow nor bindings.

"""
    parse_comment(p::Parser, tok::Token) -> Nothing

Parse `{% comment %} ... {% endcomment %}` by skipping its body.

The body is *not* parsed: commenting out a broken block is the main reason the
tag exists, so `{% comment %}{% if %}{% endcomment %}` is valid.  Nested
`comment` blocks are counted, so the matching `endcomment` is found.

Note the body is still *lexed*, since lexing happens before parsing; an
unterminated `{{` inside a comment is therefore still a syntax error, which is
what the reference suite expects.
"""
function parse_comment(p::Parser, tok::Token)
    depth = 1
    while true
        current = peek(p)
        current === nothing &&
            syntax_error(p, "expected '{% endcomment %}' before end of template",
                         tok.line, tok.col)
        advance!(p)
        if current.kind === TAG
            if current.name == "comment"
                depth += 1
            elseif current.name == "endcomment"
                depth -= 1
                depth == 0 && return nothing
            end
        end
    end
end

"""
    parse_cycle(p::Parser, tok::Token) -> CycleNode

Parse `{% cycle 'a', 'b' %}` and `{% cycle group: 'a', 'b' %}`.

Without a named group, the argument list itself identifies the cycle, so two
`cycle` tags with different arguments advance independently while two with the
same arguments share a position.
"""
function parse_cycle(p::Parser, tok::Token)
    args, line, col = tag_args(tok)
    isempty(args) && syntax_error(p, "cycle tag requires arguments", tok.line, tok.col)

    ep = ExprParser(tokenize_expression(args, line, col; template_name = p.template_name),
                    line, col, p.template_name)

    group = nothing
    items = Expression[parse_primary(ep)]

    # A colon after the first value means that value was the group name.
    if (next_token = peek(ep)) !== nothing && next_token.kind === COLON
        advance!(ep)
        group = only(items)
        empty!(items)
        push!(items, parse_primary(ep))
    end

    while (next_token = peek(ep)) !== nothing
        next_token.kind === COMMA ||
            syntax_error(p, "expected ',' in cycle tag", next_token.line, next_token.col)
        advance!(ep)
        push!(items, parse_primary(ep))
    end

    # Identity for an unnamed cycle: the argument text with whitespace removed,
    # so `{% cycle 1,2 %}` and `{% cycle 1, 2 %}` are the same cycle.
    key = replace(args, r"\s+" => "")
    return CycleNode(group, items, key, tok.line)
end
