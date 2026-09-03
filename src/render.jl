# Walk the AST and write to an IO.
#
# Rendering is a plain recursive walk.  `break` and `continue` travel as
# `ctx.interrupt`, which every block loop checks after each child so the signal
# unwinds up to the nearest `{% for %}`.

"""
    render_nodes(io, nodes, ctx)

Render a node list in order, stopping early if a `break` or `continue` is
pending.
"""
function render_nodes(io::IO, nodes::Vector{Node}, ctx::Context)
    for node in nodes
        render_node(io, node, ctx)
        ctx.interrupt === :none || return nothing
    end
    return nothing
end

"""
    is_blank_node(node) -> Bool

Whether `node` can only ever produce whitespace.

Liquid drops the output of a block whose body is entirely blank, which is why
`{% if true %}  {% endif %}` renders nothing at all rather than two spaces. The
rule is about the *kind* of node, not its rendered value: an output statement
is never blank even when it renders empty, so `{{ '' }}` inside a block keeps
that block's whitespace.
"""
is_blank_node(node::TextNode) = all(isspace, node.text)
is_blank_node(node::IfNode) =
    all(branch -> all_blank(branch.body), node.branches) && all_blank(node.else_body)
is_blank_node(node::CaseNode) = all(branch -> all_blank(branch.body), node.branches)
is_blank_node(node::ForNode) = all_blank(node.body) && all_blank(node.else_body)
# These write nothing themselves; their effect is on the context.
is_blank_node(::Union{AssignNode,CaptureNode,BreakNode,ContinueNode}) = true
# These do write something, even when it is empty.
is_blank_node(::Union{OutputNode,EchoNode,CycleNode,IncrementNode,DecrementNode}) = false
# A node type from outside the package is assumed to produce output.
is_blank_node(::Node) = false

all_blank(nodes::Vector{Node}) = all(is_blank_node, nodes)

"""
    render_block(io, nodes, ctx; blank = all_blank(nodes))

Render the body of a block tag, discarding the output when the body is blank.

The nodes are still rendered, into a throwaway buffer, because a blank body can
carry side effects: `{% if true %}{% assign x = 1 %} {% endif %}` sets `x`.
"""
function render_block(io::IO, nodes::Vector{Node}, ctx::Context;
                      blank::Bool = all_blank(nodes))
    blank || return render_nodes(io, nodes, ctx)
    return render_nodes(IOBuffer(), nodes, ctx)
end

"""
    render_node(io, node, ctx)

Render one node.  Add a method for your own [`Node`](@ref) type to make a
custom tag renderable.
"""
function render_node end

render_node(io::IO, node::TextNode, ::Context) = (print(io, node.text); nothing)

function render_node(io::IO, node::OutputNode, ctx::Context)
    text = to_liquid_string(evaluate(node.expr, ctx))
    print(io, ctx.env.autoescape ? escape_html(text) : text)
    return nothing
end

function render_node(io::IO, node::IfNode, ctx::Context)
    # Blankness is a property of the whole tag, not of the arm that runs: an
    # unreachable `{% else %}` holding an output statement keeps the block's
    # whitespace, so the flag is computed from the node and reused.
    blank = is_blank_node(node)
    for branch in node.branches
        if is_truthy(evaluate(branch.condition, ctx))
            return render_block(io, branch.body, ctx; blank)
        end
    end
    return render_block(io, node.else_body, ctx; blank)
end

render_node(::IO, node::BreakNode, ctx::Context) = (ctx.interrupt = :break; nothing)
render_node(::IO, node::ContinueNode, ctx::Context) = (ctx.interrupt = :continue; nothing)

function render_node(io::IO, node::ForNode, ctx::Context)
    items = to_iterable(evaluate(node.iterable, ctx))

    name = loop_name(node)
    offset = node.continue_offset ? get(ctx.loop_positions, name, 0) :
             loop_modifier(node.offset, ctx, "offset", 0)
    limit = loop_modifier(node.limit, ctx, "limit", nothing)

    # offset and limit slice the collection before `reversed` flips it.
    # The slice is taken by indexing rather than by collecting: a range stays a
    # range, so `{% for i in (1..1000000000) %}` does not allocate a billion
    # elements before the loop even starts.
    #
    # A negative offset does not count from the end here: it clamps to the
    # start of the slice, but keeps its raw value when computing where the
    # slice ends and where a later `offset: continue` resumes.  That is what
    # makes `offset: -2` over (0..3) render everything while `offset: continue`
    # then picks up at 2, and `offset: -2 limit: 3` render just one item.
    total = length(items)
    first_index = max(offset, 0) + 1
    last_index = limit === nothing ? total : clamp(offset + limit, 0, total)
    items = last_index < first_index ? items[1:0] : items[first_index:last_index]
    node.reversed && (items = reverse(items))

    ctx.loop_positions[name] = offset + length(items)

    isempty(items) && return render_block(io, node.else_body, ctx)

    loop = ForLoop(name, 0, length(items), current_forloop(ctx))
    # Computed once, not per iteration.
    body_is_blank = all_blank(node.body)
    push_scope!(ctx)
    try
        set_local!(ctx, "forloop", loop)
        for (i, item) in enumerate(items)
            loop.index0 = i - 1
            set_local!(ctx, node.varname, item)
            render_block(io, node.body, ctx; blank = body_is_blank)

            if ctx.interrupt === :break
                ctx.interrupt = :none
                break
            elseif ctx.interrupt === :continue
                ctx.interrupt = :none
            end
        end
    finally
        pop_scope!(ctx)
    end
    return nothing
end

function render_node(io::IO, node::CaseNode, ctx::Context)
    subject = evaluate(node.subject, ctx)
    matched = false
    # As with `if`, an arm that never runs still decides whether the block is
    # blank.
    blank = is_blank_node(node)

    # Arms are evaluated in order and none of them stops the walk: every `when`
    # value that matches renders the body again, and an `else` renders whenever
    # nothing has matched yet.
    for branch in node.branches
        if branch.values === nothing
            matched || render_block(io, branch.body, ctx; blank)
        else
            for value in branch.values
                if liquid_equal(subject, evaluate(value, ctx))
                    matched = true
                    render_block(io, branch.body, ctx; blank)
                end
                ctx.interrupt === :none || return nothing
            end
        end
        ctx.interrupt === :none || return nothing
    end
    return nothing
end

function render_node(::IO, node::AssignNode, ctx::Context)
    # Assignment goes to the outermost scope, so it survives the block it is in.
    set_global!(ctx, node.name, evaluate(node.expr, ctx))
    return nothing
end

function render_node(::IO, node::CaptureNode, ctx::Context)
    buffer = IOBuffer()
    render_nodes(buffer, node.body, ctx)
    set_global!(ctx, node.name, String(take!(buffer)))
    return nothing
end

function render_node(io::IO, node::EchoNode, ctx::Context)
    text = to_liquid_string(evaluate(node.expr, ctx))
    print(io, ctx.env.autoescape ? escape_html(text) : text)
    return nothing
end

function render_node(io::IO, node::IncrementNode, ctx::Context)
    value = get(ctx.counters, node.name, 0)
    ctx.counters[node.name] = value + 1
    print(io, to_liquid_string(value))
    return nothing
end

function render_node(io::IO, node::DecrementNode, ctx::Context)
    # Decrement subtracts first and increment adds last, which is why counters
    # start at -1 here and at 0 there.
    value = get(ctx.counters, node.name, 0) - 1
    ctx.counters[node.name] = value
    print(io, to_liquid_string(value))
    return nothing
end

function render_node(io::IO, node::CycleNode, ctx::Context)
    key = node.group === nothing ? "\0list:" * node.key :
          "\0group:" * to_liquid_string(evaluate(node.group, ctx))

    position = get(ctx.cycles, key, 0)
    # The position belongs to the group but the values come from this call, so
    # a position past the end of *this* argument list yields nothing.  That is
    # what makes `{% cycle a: '1','2' %}{% cycle a: '1','2','3' %}{% cycle a: '1' %}`
    # render "12" rather than "121".
    if position < length(node.items)
        print(io, to_liquid_string(evaluate(node.items[position+1], ctx)))
    end

    position += 1
    ctx.cycles[key] = position >= length(node.items) ? 0 : position
    return nothing
end

# `limit:` and `offset:` accept a variable, so they are evaluated here; a value
# that is not a number is an error, matching the reference suite.
function loop_modifier(expr::Union{Nothing,Expression}, ctx::Context,
                       name::AbstractString, default)
    expr === nothing && return default
    value = evaluate(expr, ctx)
    number = to_number(value)
    number === nothing && throw(LiquidArgumentError(
        "$name must be a number, got $(type_name(value))", 0, 0;
        template_name = ctx.template_name))
    # Returned as written, negatives included: the loop clamps where it slices
    # but needs the raw value to record where `offset: continue` resumes.
    return trunc(Int, number)
end

"""
    to_iterable(x)

The sequence a `{% for %}` loop walks.

Arrays and ranges iterate as themselves and a mapping iterates as `[key, value]`
pairs.  A non-empty string is a single item, not its characters, so
`{% for i in 'hello' %}` runs once and `{% for i in '' %}` not at all.  nil and numbers iterate as nothing at all,
which sends the loop to its `{% else %}` body.
"""
to_iterable(x::AbstractVector) = x
to_iterable(x::AbstractRange) = x
to_iterable(x::Tuple) = collect(x)
to_iterable(d::AbstractDict) = [Any[k, v] for (k, v) in d]
to_iterable(x::AbstractString) = isempty(x) ? () : (x,)
to_iterable(::Any) = ()

"""
    escape_html(s) -> String

Escape the five characters that matter in HTML text and attributes.  Used by
`autoescape` and by the `escape` filter.
"""
function escape_html(s::AbstractString)
    io = IOBuffer()
    for c in s
        if c === '&'
            print(io, "&amp;")
        elseif c === '<'
            print(io, "&lt;")
        elseif c === '>'
            print(io, "&gt;")
        elseif c === '"'
            print(io, "&#34;")
        elseif c === '\''
            print(io, "&#39;")
        else
            print(io, c)
        end
    end
    return String(take!(io))
end
