# Stage 2c: drive the token stream into a node list.
#
# The parser itself knows about exactly three things: text, output statements,
# and "some tag".  Every tag is looked up in a registry and parsed by its own
# function, so a user can add a tag without touching this file.

"""
    TagDef(name, parse, inner = String[])

A registered tag.

- `parse` is called as `parse(p::Parser, tok::Token)` with the parser
  positioned just after the tag token, and must return a [`Node`](@ref) or
  `nothing` (for a tag that produces no output, such as `comment`).
- `inner` lists the tag names that belong to this tag's block and may not
  appear on their own, e.g. `["elsif", "else", "endif"]` for `if`.  It is used
  only to report a stray `{% endif %}` as an unexpected tag rather than an
  unknown one.
"""
struct TagDef
    name::String
    parse::Function
    inner::Vector{String}
end

TagDef(name::AbstractString, parse::Function; inner = String[]) =
    TagDef(String(name), parse, String[String(x) for x in inner])

"""
    Parser

Cursor over a token vector, plus the tag registry to resolve tags against.

Tag parse functions receive one of these and drive it with [`parse_block!`](@ref),
[`peek`](@ref) and [`advance!`](@ref).
"""
mutable struct Parser
    tokens::Vector{Token}
    pos::Int
    tags::Dict{String,TagDef}
    template_name::String
    inner_names::Set{String}
end

function Parser(tokens::Vector{Token}, tags::Dict{String,TagDef};
                template_name::AbstractString = "")
    inner = Set{String}()
    for def in values(tags), name in def.inner
        push!(inner, name)
    end
    Parser(tokens, 1, tags, String(template_name), inner)
end

"""
    peek(p, ahead = 0) -> Union{Token,Nothing}

The token `ahead` positions from the cursor without consuming it, or `nothing`
past the end. Also defined for the expression parser, returning an `ExprToken`.
"""
peek(p::Parser, ahead::Int = 0) =
    p.pos + ahead <= length(p.tokens) ? p.tokens[p.pos+ahead] : nothing

"""
    advance!(p) -> Token

Consume and return the token at the cursor. Also defined for the expression
parser, returning an `ExprToken`.
"""
function advance!(p::Parser)
    tok = peek(p)
    tok === nothing && throw(LiquidSyntaxError("unexpected end of template", 1, 1;
                                               template_name = p.template_name))
    p.pos += 1
    return tok
end

"""
    syntax_error(p::Parser, msg, line, col)

Raise a [`LiquidSyntaxError`](@ref) tagged with this parser's template name.
Always throws; the return type is `Union{}`.
"""
syntax_error(p::Parser, msg::AbstractString, line::Integer, col::Integer) =
    throw(LiquidSyntaxError(msg, line, col; template_name = p.template_name))

"""
    register_tag!(tags::Dict{String,TagDef}, def::TagDef)

Add `def` to a tag registry, replacing any tag of the same name.
"""
function register_tag!(tags::Dict{String,TagDef}, def::TagDef)
    tags[def.name] = def
    return tags
end

"""
    parse_block!(p::Parser, stop) -> (nodes, stop_token)

Parse nodes until one of the tag names in `stop` is reached, without consuming
that tag.  This is what a block tag calls to read its body.

Reaching the end of the template first is a syntax error naming what was
expected.
"""
function parse_block!(p::Parser, stop::Vector{String})
    nodes = Node[]
    while true
        tok = peek(p)
        if tok === nothing
            expected = join(("'{% $s %}'" for s in stop), " or ")
            line, col = _last_position(p)
            syntax_error(p, "expected $expected before end of template", line, col)
        end
        if tok.kind === TAG && tok.name in stop
            advance!(p)
            return nodes, tok
        end
        node = parse_one!(p)
        node === nothing || push!(nodes, node)
    end
end

# Parse a single node.  Returns nothing for constructs that produce no output.
function parse_one!(p::Parser)
    tok = advance!(p)

    if tok.kind === TEXT
        return TextNode(tok.value)
    elseif tok.kind === OUTPUT
        isempty(tok.value) &&
            syntax_error(p, "empty output statement", tok.line, tok.col)
        expr = parse_filtered(tok.value, tok.line, tok.col; template_name = p.template_name)
        return OutputNode(expr, tok.line)
    end

    # tok.kind === TAG
    if isempty(tok.name)
        syntax_error(p, "malformed tag", tok.line, tok.col)
    end
    def = get(p.tags, tok.name, nothing)
    if def === nothing
        if tok.name in p.inner_names
            syntax_error(p, "unexpected tag '$(tok.name)'", tok.line, tok.col)
        end
        syntax_error(p, "unknown tag '$(tok.name)'", tok.line, tok.col)
    end
    return def.parse(p, tok)
end

function _last_position(p::Parser)
    isempty(p.tokens) && return 1, 1
    tok = p.tokens[end]
    return tok.line, tok.col
end

"""
    parse_nodes(source, tags; template_name = "") -> Vector{Node}

Parse a whole template: tokenize `source`, apply whitespace control, and turn
the result into a node list using the tag registry `tags`.
"""
function parse_nodes(source::AbstractString, tags::Dict{String,TagDef};
                     template_name::AbstractString = "")
    tokens = apply_whitespace_control(tokenize(source; template_name))
    p = Parser(tokens, tags; template_name)
    nodes = Node[]
    while peek(p) !== nothing
        node = parse_one!(p)
        node === nothing || push!(nodes, node)
    end
    return nodes
end

"""
    default_tags() -> Dict{String,TagDef}

A fresh registry holding the built-in tags.  Each [`Environment`] gets its own
copy, so registering a tag in one never affects another.
"""
function default_tags()
    tags = Dict{String,TagDef}()
    register_tag!(tags, TagDef("if", parse_if; inner = ["elsif", "else", "endif"]))
    register_tag!(tags, TagDef("for", parse_for; inner = ["else", "endfor"]))
    register_tag!(tags, TagDef("break", parse_break))
    register_tag!(tags, TagDef("continue", parse_continue))
    register_tag!(tags, TagDef("unless", parse_unless;
                               inner = ["elsif", "else", "endunless"]))
    register_tag!(tags, TagDef("case", parse_case;
                               inner = ["when", "else", "endcase"]))
    register_tag!(tags, TagDef("assign", parse_assign))
    register_tag!(tags, TagDef("capture", parse_capture; inner = ["endcapture"]))
    register_tag!(tags, TagDef("echo", parse_echo))
    register_tag!(tags, TagDef("increment", parse_increment))
    register_tag!(tags, TagDef("decrement", parse_decrement))
    register_tag!(tags, TagDef("cycle", parse_cycle))
    register_tag!(tags, TagDef("comment", parse_comment; inner = ["endcomment"]))
    return tags
end
