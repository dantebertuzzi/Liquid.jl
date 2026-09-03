"""
    LiquidError <: Exception

Supertype of every error raised by Liquid.jl.

Liquid is a lenient language: rendering a template is not supposed to fail.
Undefined variables render as the empty string, incompatible types are coerced
rather than rejected, and `nothing` behaves like a false value.  Errors are
therefore concentrated in the parsing stage, where a malformed template can and
should be reported with a precise location.
"""
abstract type LiquidError <: Exception end

"""
    LiquidSyntaxError(msg, line, col; template_name = "")

Raised when a template cannot be parsed.  Carries the 1-based `line` and `col`
of the offending construct so the message can point at it.
"""
struct LiquidSyntaxError <: LiquidError
    msg::String
    line::Int
    col::Int
    template_name::String
end

LiquidSyntaxError(msg::AbstractString, line::Integer, col::Integer; template_name::AbstractString = "") =
    LiquidSyntaxError(String(msg), Int(line), Int(col), String(template_name))

function Base.showerror(io::IO, err::LiquidSyntaxError)
    where_ = isempty(err.template_name) ? "" : "$(err.template_name):"
    print(io, "LiquidSyntaxError: ", err.msg, " at ", where_, err.line, ":", err.col)
end

"""
    LiquidArgumentError(msg, line, col; template_name = "")

Raised at render time for the few operations Liquid does *not* forgive: an
order comparison between incompatible types (`{% if '2' > 1 %}`), a filter
called with the wrong number of arguments, or a loop modifier that is not a
number.

Everything else is lenient by design; see [`LiquidError`](@ref).
"""
struct LiquidArgumentError <: LiquidError
    msg::String
    line::Int
    col::Int
    template_name::String
end

LiquidArgumentError(msg::AbstractString, line::Integer, col::Integer;
                    template_name::AbstractString = "") =
    LiquidArgumentError(String(msg), Int(line), Int(col), String(template_name))

function Base.showerror(io::IO, err::LiquidArgumentError)
    where_ = isempty(err.template_name) ? "" : "$(err.template_name):"
    print(io, "LiquidArgumentError: ", err.msg, " at ", where_, err.line, ":", err.col)
end

"""
    LiquidUndefinedError(name, line, col; template_name = "")

Raised for an undefined variable, but only when the environment was built with
`strict_variables = true`.  By default an undefined variable renders as the
empty string and no error is raised.
"""
struct LiquidUndefinedError <: LiquidError
    name::String
    line::Int
    col::Int
    template_name::String
end

LiquidUndefinedError(name::AbstractString, line::Integer, col::Integer;
                     template_name::AbstractString = "") =
    LiquidUndefinedError(String(name), Int(line), Int(col), String(template_name))

function Base.showerror(io::IO, err::LiquidUndefinedError)
    where_ = isempty(err.template_name) ? "" : "$(err.template_name):"
    print(io, "LiquidUndefinedError: undefined variable ", repr(err.name),
          " at ", where_, err.line, ":", err.col)
end
