# The `date` filter, and the strftime translation it needs.
#
# Liquid's date formats are Ruby's strftime codes, which are not Julia's
# `Dates` format strings.  Rather than translating one mini-language into the
# other, each code is rendered directly from the DateTime here: the mapping
# stays explicit and each code is testable on its own.

using Dates

# Formats accepted when parsing a date out of a string, tried in order.
const DATE_FORMATS = [
    dateformat"yyyy-mm-ddTHH:MM:SS",
    dateformat"yyyy-mm-dd HH:MM:SS",
    dateformat"yyyy-mm-dd",
    dateformat"U d, yyyy",
    dateformat"u d, yyyy",
    dateformat"d U yyyy",
    dateformat"d u yyyy",
    dateformat"mm/dd/yyyy",
]

"""
    to_datetime(value) -> Union{DateTime,Nothing}

Interpret `value` as a moment in time, or `nothing` when it cannot be read as
one.

An integer, or a string of digits, is a Unix timestamp.  `"now"` and `"today"`
mean the current time.  Anything else is tried against [`DATE_FORMATS`](@ref).
"""
to_datetime(value::DateTime) = value
to_datetime(value::Date) = DateTime(value)
to_datetime(value::Integer) = unix2datetime(value)

function to_datetime(value::AbstractString)
    text = strip(value)
    (text == "now" || text == "today") && return Dates.now()
    # Only unsigned digits count as a timestamp.  A signed run of digits is not
    # a date at all, and must not fall through to the format list, where a
    # lenient parse would turn "-1152098955" into some far-future year.
    occursin(r"^\d+$", text) && return unix2datetime(parse(Int, text))
    occursin(r"^[-+]\d+$", text) && return nothing
    for format in DATE_FORMATS
        parsed = tryparse(DateTime, text, format)
        parsed === nothing || return parsed
    end
    return nothing
end

to_datetime(::Any) = nothing

const DAY_NAMES = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
const MONTH_NAMES = ("January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December")

pad2(n::Integer) = string(n; pad = 2)

"""
    strftime_field(dt::DateTime, code::Char, no_pad::Bool) -> String

Render one strftime code.  `no_pad` is set by the `-` modifier, as in `%-d`.

Unknown codes render as themselves, preceded by the `%`, which is how Ruby
treats them.
"""
function strftime_field(dt::DateTime, code::Char, no_pad::Bool)
    number(n) = no_pad ? string(n) : pad2(n)

    code == 'Y' && return string(Dates.year(dt))
    code == 'y' && return pad2(mod(Dates.year(dt), 100))
    code == 'C' && return pad2(Dates.year(dt) ÷ 100)
    code == 'm' && return number(Dates.month(dt))
    code == 'd' && return number(Dates.day(dt))
    code == 'e' && return lpad(Dates.day(dt), 2)
    code == 'j' && return no_pad ? string(Dates.dayofyear(dt)) : string(Dates.dayofyear(dt); pad = 3)
    code == 'H' && return number(Dates.hour(dt))
    code == 'k' && return lpad(Dates.hour(dt), 2)
    code == 'I' && return number(hour12(dt))
    code == 'l' && return lpad(hour12(dt), 2)
    code == 'M' && return number(Dates.minute(dt))
    code == 'S' && return number(Dates.second(dt))
    code == 'L' && return string(Dates.millisecond(dt); pad = 3)
    code == 'N' && return string(Dates.millisecond(dt) * 1_000_000; pad = 9)
    code == 'p' && return Dates.hour(dt) < 12 ? "AM" : "PM"
    code == 'P' && return Dates.hour(dt) < 12 ? "am" : "pm"
    code == 'A' && return DAY_NAMES[Dates.dayofweek(dt)]
    code == 'a' && return first(DAY_NAMES[Dates.dayofweek(dt)], 3)
    code == 'B' && return MONTH_NAMES[Dates.month(dt)]
    code in ('b', 'h') && return first(MONTH_NAMES[Dates.month(dt)], 3)
    # Ruby numbers weekdays from Sunday for %w and from Monday for %u.
    code == 'w' && return string(mod(Dates.dayofweek(dt), 7))
    code == 'u' && return string(Dates.dayofweek(dt))
    code == 'U' && return pad2(week_of_year(dt, 7))
    code == 'W' && return pad2(week_of_year(dt, 1))
    code == 's' && return string(round(Int, Dates.datetime2unix(dt)))
    # No timezone is carried, so these report UTC.
    code == 'Z' && return "UTC"
    code == 'z' && return "+0000"
    code == 'n' && return "\n"
    code == 't' && return "\t"
    code == 'D' && return strftime(dt, "%m/%d/%y")
    code == 'F' && return strftime(dt, "%Y-%m-%d")
    code == 'T' && return strftime(dt, "%H:%M:%S")
    code == 'R' && return strftime(dt, "%H:%M")
    code == 'r' && return strftime(dt, "%I:%M:%S %p")
    code == 'x' && return strftime(dt, "%m/%d/%y")
    code == 'X' && return strftime(dt, "%H:%M:%S")
    code == 'c' && return strftime(dt, "%a %b %e %H:%M:%S %Y")
    return "%" * string(code)
end

hour12(dt::DateTime) = (h = mod(Dates.hour(dt), 12); h == 0 ? 12 : h)

# Week of the year counting from the first `start_day` (7 = Sunday, 1 = Monday).
function week_of_year(dt::DateTime, start_day::Int)
    first_of_year = Date(Dates.year(dt), 1, 1)
    offset = mod(Dates.dayofweek(first_of_year) - start_day, 7)
    return (Dates.dayofyear(dt) + offset - 1) ÷ 7
end

"""
    strftime(dt::DateTime, format) -> String

Render `dt` using Ruby strftime codes.  `%%` is a literal percent sign, and a
`-` between the `%` and the code drops zero padding, as in `%-d`.
"""
function strftime(dt::DateTime, format::AbstractString)
    out = IOBuffer()
    i = firstindex(format)
    stop = lastindex(format)

    while i <= stop
        c = format[i]
        if c != '%'
            print(out, c)
            i = nextind(format, i)
            continue
        end

        j = nextind(format, i)
        if j > stop
            print(out, '%')
            break
        end
        if format[j] == '%'
            print(out, '%')
            i = nextind(format, j)
            continue
        end

        no_pad = format[j] == '-'
        no_pad && (j = nextind(format, j))
        if j > stop
            print(out, "%-")
            break
        end

        print(out, strftime_field(dt, format[j], no_pad))
        i = nextind(format, j)
    end
    return String(take!(out))
end

"""
    date_filter(input, format)

`{{ "March 14, 2016" | date: "%b %d, %y" }}`.

The input may be a `DateTime`, a Unix timestamp, `"now"`, or a date string in
one of several common formats.  An input that cannot be read as a date, or a
format that is not a string, is returned unchanged rather than raising, which
is what makes `{{ x | date: nil }}` a no-op.
"""
function date_filter(input, format)
    (format === nothing || format === missing) && return input
    (input === nothing || input === missing) && return nothing

    moment = to_datetime(input)
    moment === nothing && return input
    return strftime(moment, to_liquid_string(format))
end
