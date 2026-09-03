```@meta
CurrentModule = Liquid
```

# Liquid.jl

A pure-Julia implementation of the [Liquid](https://shopify.github.io/liquid/)
template language, the one Shopify created and that Jekyll and many others use.

Liquid exists to be safe to hand to people you do not fully trust. The language
has no way to name a function, reach a field its author did not expose, or touch
the host process; the worst a hostile template can do is produce useless output.
This package keeps that property: **rendering a template never evaluates Julia
code**. There is no `eval`, no `getproperty`, and no reflection anywhere on the
render path.

```jldoctest
julia> using Liquid

julia> render("Hello, {{ name }}!"; name = "World")
"Hello, World!"
```

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/dantebertuzzi/Liquid.jl")
```

Julia 1.10 or later. The only runtime dependency is `Dates`, from the standard
library.

## Parse once, render many times

Parsing is the expensive half, and a [`Template`](@ref) is immutable, so a
template used more than once should be parsed once.

```jldoctest
julia> using Liquid

julia> template = parse_template("Hello, {{ name }}!");

julia> render(template; name = "World")
"Hello, World!"

julia> render(template; name = "Liquid")
"Hello, Liquid!"
```

## Configuration

An [`Environment`](@ref) holds everything a template is parsed and rendered
against: where templates are loaded from, which tags and filters exist, and how
strict rendering is. Each environment owns its own registries, so registering a
tag in one never affects another.

```julia
env = Environment(
    loader = FileSystemLoader("./templates"),
    autoescape = true,
    strict_variables = false,
)

template = get_template(env, "letter.liquid")
render(template, Dict("owners" => owners))
```

## The two commitments

### Leniency

Liquid almost never fails while rendering. An undefined variable is the empty
string, `nothing` and `missing` behave as false, and incompatible types are
coerced rather than rejected.

```jldoctest
julia> using Liquid

julia> render("[{{ nope }}]")
"[]"

julia> render("[{{ a.b.c[0] }}]"; a = 1)
"[]"

julia> render("{{ 'hello' | plus: 1 }}")
"1"
```

Truthiness has one rule, and it catches people out: **only `false` and nil are
false**. Zero is true, the empty string is true, the empty array is true.

```jldoctest
julia> using Liquid

julia> render("{% if x %}yes{% else %}no{% endif %}"; x = 0)
"yes"

julia> render("{% if x %}yes{% else %}no{% endif %}"; x = "")
"yes"

julia> render("{% if x %}yes{% else %}no{% endif %}"; x = nothing)
"no"
```

Syntax errors are a different matter: those are raised, with a line and column.

```jldoctest
julia> using Liquid

julia> render("hello\n{% if %}x{% endif %}")
ERROR: LiquidSyntaxError: if tag requires a condition at 2:4
[...]
```

There are two deliberate exceptions to leniency at render time, both matching
the reference implementation: an order comparison between different types, and
a filter called with arguments it does not accept.

```jldoctest
julia> using Liquid

julia> render("{% if 'abc' < 'acb' %}yes{% endif %}")
"yes"

julia> render("{% if '2' > 1 %}yes{% endif %}")
ERROR: LiquidArgumentError: cannot compare a string with a number at 1:11
[...]
```

Set `strict_variables = true` on an environment to turn undefined variables
into errors as well.

### Security

Values of your own types are opaque until you say otherwise. There is no
reflection fallback: a struct that has not opted in exposes nothing, and only
the field names its author listed are ever read. See [Exposing your own types](data.md#Exposing-your-own-types).

## Conformance

Validated against [Golden Liquid](https://github.com/jg-rp/golden-liquid), the
reference suite `python-liquid` uses.

```
862 / 865 in-scope cases pass (99.7%)
```

The suite has 1098 cases; 233 exercise features outside the v0.1 scope and are
skipped rather than counted as passes. Of the three that remain, two are cases
the suite contradicts itself on, marking the same template valid under one
strictness mode and invalid under another.

## Scope

Implemented: `assign`, `capture`, `if`/`elsif`/`else`, `unless`, `case`/`when`,
`for` (with `limit`, `offset`, `reversed`, `else`, `break`, `continue`),
`cycle`, `increment`, `decrement`, `raw`, `comment`, `echo`, and the standard
filter set.

Planned for v0.2: `include`, `render`, template inheritance, caching loaders,
`tablerow`, and the `liquid` tag.
