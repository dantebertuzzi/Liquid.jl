# Evaluate an expression against a context.
#
# Interpretation, not compilation: every function here walks the AST and reads
# values.  Nothing in this file can call a Julia function named by the template,
# and there is no `eval` anywhere in the package.

"""
    evaluate(expr, ctx::Context) -> Any

Evaluate `expr` against `ctx`.  Undefined names become `nothing` unless the
environment sets `strict_variables`.
"""
function evaluate end

evaluate(e::LiteralExpr, ::Context) = e.value

function evaluate(e::VariableExpr, ctx::Context)
    key = to_lookup_key(evaluate(e.path[1], ctx))
    value = key isa AbstractString ? lookup(ctx, key) : UNDEFINED
    value = walk_path(value, e.path, 2, ctx)
    value === UNDEFINED || return value

    if ctx.env.strict_variables
        throw(LiquidUndefinedError(variable_name(e), e.line, e.col;
                                   template_name = ctx.template_name))
    end
    return nothing
end

# Walk `path[from:end]` into `value`, stopping as soon as something is missing.
function walk_path(value, path::Vector{Expression}, from::Int, ctx::Context)
    for i in from:lastindex(path)
        value === UNDEFINED && return UNDEFINED
        value = resolve_key(value, to_lookup_key(evaluate(path[i], ctx)))
    end
    return value
end

# Reconstruct `a.b[0]` from a path, for the strict_variables message.
function variable_name(e::VariableExpr)
    io = IOBuffer()
    for (i, segment) in enumerate(e.path)
        if segment isa LiteralExpr && segment.value isa AbstractString
            i == 1 ? print(io, segment.value) : print(io, ".", segment.value)
        elseif segment isa LiteralExpr
            print(io, "[", to_liquid_string(segment.value), "]")
        else
            print(io, "[...]")
        end
    end
    return String(take!(io))
end

function evaluate(e::RangeExpr, ctx::Context)
    # An endpoint that is not a number counts as 0, so `(start..end)` with
    # start "foo" and end 5 iterates 0 to 5.  A start above the end simply
    # gives an empty range, which is how `(5..1)` renders nothing.
    start = range_endpoint(e.start, evaluate(e.start, ctx), ctx)
    stop = range_endpoint(e.stop, evaluate(e.stop, ctx), ctx)
    return start:stop
end

# A float endpoint written literally is truncated, `(1.4..5)` iterating from 1,
# but a float arriving from a variable is an error.  The distinction is the
# reference implementation's: a literal is narrowed when the template is read,
# while a runtime value has to already be a whole number.
function range_endpoint(expr::Expression, value, ctx::Context)
    expr isa LiteralExpr && return range_endpoint_literal(value)
    if value isa AbstractFloat
        throw(LiquidArgumentError("range bounds must be whole numbers, got $value",
                                  0, 0; template_name = ctx.template_name))
    end
    n = to_number(value)
    return n === nothing ? 0 : trunc(Int, n)
end

function range_endpoint_literal(value)
    n = to_number(value)
    return n === nothing ? 0 : trunc(Int, n)
end

function evaluate(e::CompareExpr, ctx::Context)
    left = evaluate(e.left, ctx)
    right = evaluate(e.right, ctx)
    try
        return compare(e.op, left, right)
    catch err
        err isa IncomparableValues || rethrow()
        # Report the operands in the order the template wrote them.  `>` is
        # implemented by swapping the arguments to `<`, so the values carried by
        # the exception are the other way round.
        throw(LiquidArgumentError(
            "cannot compare $(type_name(left)) with $(type_name(right))",
            e.line, e.col; template_name = ctx.template_name))
    end
end

type_name(::Nothing) = "nil"
type_name(::Missing) = "nil"
type_name(::Bool) = "boolean"
type_name(::Number) = "a number"
type_name(::AbstractString) = "a string"
type_name(::AbstractVector) = "an array"
type_name(::AbstractDict) = "a hash"
type_name(x) = string(nameof(typeof(x)))

function evaluate(e::BooleanExpr, ctx::Context)
    left = is_truthy(evaluate(e.left, ctx))
    if e.op === :and
        return left && is_truthy(evaluate(e.right, ctx))
    else
        return left || is_truthy(evaluate(e.right, ctx))
    end
end

evaluate(e::NotExpr, ctx::Context) = !is_truthy(evaluate(e.operand, ctx))

function evaluate(e::FilteredExpr, ctx::Context)
    value = evaluate(e.expr, ctx)
    for call in e.filters
        value = apply_filter(value, call, ctx)
    end
    return value
end

"""
    apply_filter(value, call::FilterCall, ctx::Context) -> Any

Look the filter up in the environment and call it.

An unknown filter is a no-op unless `strict_filters` is set.  A filter called
with arguments it does not accept raises [`LiquidArgumentError`](@ref); that is
where `{{ "hello" | upcase: 5 }}` is rejected.
"""
function apply_filter(value, call::FilterCall, ctx::Context)
    f = get(ctx.env.filters, call.name, nothing)
    if f === nothing
        ctx.env.strict_filters && throw(LiquidArgumentError(
            "unknown filter '$(call.name)'", call.line, call.col;
            template_name = ctx.template_name))
        return value
    end

    args = Any[evaluate(a, ctx) for a in call.args]
    kwargs = Pair{Symbol,Any}[Symbol(k) => evaluate(v, ctx) for (k, v) in call.kwargs]

    try
        return needs_context(f) ? f(ctx, value, args...; kwargs...) :
                                  f(value, args...; kwargs...)
    catch err
        # A filter that rejected its input reports why; only the position is
        # added here, since the filter cannot know it.
        if err isa FilterError
            throw(LiquidArgumentError("filter '$(call.name)': $(err.msg)",
                                      call.line, call.col;
                                      template_name = ctx.template_name))
        end
        # Only a signature mismatch on this very function becomes an argument
        # error; a MethodError raised deeper inside the filter is a real bug
        # and must not be disguised.
        (err isa MethodError && err.f === f) || rethrow()
        throw(LiquidArgumentError("filter '$(call.name)' does not take these arguments",
                                  call.line, call.col; template_name = ctx.template_name))
    end
end
