# Stage 2b: the node types the parser produces.
#
# A template is a Vector{Node}.  Nodes hold already-parsed expressions and, for
# block tags, the nested node lists of their bodies.  Nothing here knows how to
# render itself; that is the renderer's job, kept separate so the AST stays
# inspectable and testable on its own.

"""
    Node

Supertype of every node in a parsed template.

New node types can be added from outside the package: register a tag that
returns one (see [`TagDef`](@ref)) and add a `render_node` method for it.
"""
abstract type Node end

"""
    TextNode(text)

Literal template text, emitted verbatim.  The body of `{% raw %}` also arrives
as one of these.
"""
struct TextNode <: Node
    text::String
end

"""
    OutputNode(expr, line)

An `{{ expression | filters }}` statement.
"""
struct OutputNode <: Node
    expr::FilteredExpr
    line::Int
end

"""
    ConditionalBranch(condition, body)

One `if`/`elsif`/`unless` arm: the condition to test and the nodes to render
when it holds.  Not a `Node` itself.
"""
struct ConditionalBranch
    condition::Expression
    body::Vector{Node}
end

"""
    IfNode(branches, else_body, line)

A conditional.  `branches[1]` is the `if` itself and the rest are its `elsif`
arms, each tested in order; `else_body` is empty when there is no `else`.

`{% unless %}` parses into this same node with its first condition wrapped in a
[`NotExpr`](@ref), so the renderer only ever sees one shape of conditional.
"""
struct IfNode <: Node
    branches::Vector{ConditionalBranch}
    else_body::Vector{Node}
    line::Int
end

"""
    ForNode(varname, iterable, limit, offset, reversed, body, else_body, line)

A `{% for %}` loop.

`limit` and `offset` are expressions, not numbers, because Liquid allows
`{% for x in a limit: n %}` where `n` is a variable; they are `nothing` when
absent.  `continue_offset` marks the special form `offset: continue`, which
resumes where a previous loop over the same collection stopped.
`iterable_source` is the collection as written, needed for the loop's name.
`else_body` renders when the collection turns out to be empty.
"""
struct ForNode <: Node
    varname::String
    iterable::Expression
    iterable_source::String
    limit::Union{Nothing,Expression}
    offset::Union{Nothing,Expression}
    continue_offset::Bool
    reversed::Bool
    body::Vector{Node}
    else_body::Vector{Node}
    line::Int
end

"""
    loop_name(node::ForNode) -> String

The identifier Liquid gives a loop, `variable-collection`, as reported by
`{{ forloop.name }}` and used to remember where `offset: continue` should
resume.
"""
loop_name(node::ForNode) = node.varname * "-" * node.iterable_source

"""
    BreakNode(line)

`{% break %}`: stop the innermost enclosing loop.
"""
struct BreakNode <: Node
    line::Int
end

"""
    ContinueNode(line)

`{% continue %}`: skip to the next iteration of the innermost enclosing loop.
"""
struct ContinueNode <: Node
    line::Int
end

"""
    CaseBranch(values, body)

One arm of a `{% case %}`: the values a `{% when %}` tests, or `nothing` for
the `{% else %}` arm.
"""
struct CaseBranch
    values::Union{Nothing,Vector{Expression}}
    body::Vector{Node}
end

"""
    CaseNode(subject, branches, line)

A `{% case %}` block.

`branches` is kept as one ordered list, `when` and `else` arms together, rather
than split, because Liquid evaluates them in source order and does *not* stop
at the first match: every `when` whose value matches renders, and an `else`
renders whenever no `when` has matched *so far*.  So
`{% case 'x' %}{% when 'y' %}a{% else %}b{% when 'x' %}c{% endcase %}`
renders "bc".
"""
struct CaseNode <: Node
    subject::Expression
    branches::Vector{CaseBranch}
    line::Int
end

"""
    AssignNode(name, expr, line)

`{% assign name = value | filters %}`.  Assignment writes to the outermost
scope, so it outlives the block it appears in.
"""
struct AssignNode <: Node
    name::String
    expr::FilteredExpr
    line::Int
end

"""
    CaptureNode(name, body, line)

`{% capture name %}...{% endcapture %}`: render the body and bind the result to
`name` instead of writing it out.
"""
struct CaptureNode <: Node
    name::String
    body::Vector{Node}
    line::Int
end

"""
    EchoNode(expr, line)

`{% echo value | filters %}`, the tag form of an output statement.  Unlike
`{{ }}`, an empty `{% echo %}` is legal and renders nothing.
"""
struct EchoNode <: Node
    expr::FilteredExpr
    line::Int
end

"""
    CycleNode(group, items, key, line)

`{% cycle 'a', 'b' %}` or `{% cycle group: 'a', 'b' %}`.

`group` is an expression evaluated at render time, so `{% cycle a: 1, 2 %}`
follows the current value of `a`; `key` is the fallback identity used when no
group is named, derived from the argument list so that two `cycle` tags with
different arguments advance independently.
"""
struct CycleNode <: Node
    group::Union{Nothing,Expression}
    items::Vector{Expression}
    key::String
    line::Int
end

"""
    IncrementNode(name, line)

`{% increment name %}`: print the counter, then add one.  Counters live in
their own namespace, separate from variables.
"""
struct IncrementNode <: Node
    name::String
    line::Int
end

"""
    DecrementNode(name, line)

`{% decrement name %}`: subtract one from the counter, then print it.  Note the
order differs from `increment`, which is why one starts at 0 and the other
at -1.
"""
struct DecrementNode <: Node
    name::String
    line::Int
end

# Structural equality, so tests can compare parsed templates against literals.
Base.:(==)(a::CaseBranch, b::CaseBranch) = a.values == b.values && a.body == b.body
Base.:(==)(a::CaseNode, b::CaseNode) = a.subject == b.subject && a.branches == b.branches
Base.:(==)(a::AssignNode, b::AssignNode) = a.name == b.name && a.expr == b.expr
Base.:(==)(a::CaptureNode, b::CaptureNode) = a.name == b.name && a.body == b.body
Base.:(==)(a::EchoNode, b::EchoNode) = a.expr == b.expr
Base.:(==)(a::CycleNode, b::CycleNode) =
    a.group == b.group && a.items == b.items && a.key == b.key
Base.:(==)(a::IncrementNode, b::IncrementNode) = a.name == b.name
Base.:(==)(a::DecrementNode, b::DecrementNode) = a.name == b.name
Base.:(==)(::BreakNode, ::BreakNode) = true
Base.:(==)(::ContinueNode, ::ContinueNode) = true
Base.:(==)(a::TextNode, b::TextNode) = a.text == b.text
Base.:(==)(a::OutputNode, b::OutputNode) = a.expr == b.expr
Base.:(==)(a::ConditionalBranch, b::ConditionalBranch) =
    a.condition == b.condition && a.body == b.body
Base.:(==)(a::IfNode, b::IfNode) = a.branches == b.branches && a.else_body == b.else_body
Base.:(==)(a::ForNode, b::ForNode) =
    a.varname == b.varname && a.iterable == b.iterable && a.limit == b.limit &&
    a.offset == b.offset && a.continue_offset == b.continue_offset &&
    a.reversed == b.reversed && a.body == b.body && a.else_body == b.else_body
