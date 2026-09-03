```@meta
CurrentModule = Liquid
```

# Template reference

What the template language itself supports in v0.1.

## Output and whitespace

`{{ expression | filters }}` writes a value. `{% tag %}` does something.
A `-` next to a delimiter removes **all** adjacent whitespace, newlines
included.

```jldoctest
julia> using Liquid

julia> render("a  {{- x -}}  b"; x = "|")
"a|b"

julia> render("a\n\n  {%- if true %}x{% endif %}")
"ax"
```

A block whose body can only produce whitespace has its output dropped
entirely, though its side effects still happen:

```jldoctest
julia> using Liquid

julia> render("[{% if true %}  {% assign x = 9 %}  {% endif %}]{{ x }}")
"[]9"
```

## Expressions

Literals are strings, integers, floats, `true`, `false`, `nil` (or `null`),
`empty` and `blank`. Integers and floats stay distinct, and the output shows it.

Ranges are written `(1..5)`; both ends are truncated to integers.

Comparison uses `==`, `!=` (or `<>`), `>`, `<`, `>=`, `<=` and `contains`.

!!! warning "and and or"
    In Liquid, `and` and `or` share **one precedence level** and associate to
    the **right**. This is not the precedence Julia, Python or Ruby give them,
    and it is a classic source of divergence.

    ```jldoctest
    julia> using Liquid

    julia> render("{% if true and false and false or true %}yes{% endif %}")
    ""
    ```

    That reads as `true and (false and (false or true))`, which is false. Under
    the usual precedence it would be `(true and false and false) or true`, which
    is true.

## Tags

### Conditionals

```liquid
{% if a %}...{% elsif b %}...{% else %}...{% endif %}
{% unless a %}...{% else %}...{% endunless %}
```

`unless` negates only its first condition; `elsif` arms read as written.

Arms after the first `{% else %}` are parsed but never rendered, matching the
reference implementation: `{% if false %}1{% else %}2{% else %}3{% endif %}`
renders `2`.

### case

```liquid
{% case x %}{% when 1 %}...{% when 2, 3 %}...{% else %}...{% endcase %}
```

Values are separated by commas or by `or`. Two behaviours differ from a
`switch` and are worth knowing:

- Evaluation does **not** stop at the first match. Every `when` whose value
  matches renders, and the body repeats once per matching value.
- An `else` renders whenever no `when` has matched *so far*, in source order.

```jldoctest
julia> using Liquid

julia> render("{% case 'x' %}{% when 'y' %}a{% else %}b{% when 'x' %}c{% endcase %}")
"bc"
```

### for

```liquid
{% for item in collection limit: 2 offset: 1 reversed %}
  {{ item }}
{% else %}
  nothing
{% endfor %}
```

`limit` and `offset` may be variables. `offset: continue` resumes where the
previous loop over the same collection stopped. `{% break %}` and
`{% continue %}` affect the innermost loop.

Arrays and ranges iterate as themselves; a mapping iterates as `[key, value]`
pairs; a non-empty string is a **single item**, not its characters.

Inside the body, `forloop` carries `index`, `index0`, `rindex`, `rindex0`,
`first`, `last`, `length`, `name` and `parentloop`. These are relative to the
slice `limit` and `offset` produced, not to the original collection.

```jldoctest
julia> using Liquid

julia> render("{% for i in (1..3) %}{{ forloop.index }}/{{ forloop.rindex }} {% endfor %}")
"1/3 2/2 3/1 "
```

### Assignment

```liquid
{% assign name = value | filters %}
{% capture name %}...{% endcapture %}
```

Both write to the outermost scope, so an assignment inside a loop outlives it.

### Counters

```liquid
{% increment name %}   {% decrement name %}
```

`increment` prints then adds one, starting at 0; `decrement` subtracts then
prints, starting at -1. They share a counter, in a namespace **separate** from
variables:

```jldoctest
julia> using Liquid

julia> render("{% assign f = 5 %}{{ f }} {% increment f %} {% increment f %} {{ f }}")
"5 0 1 5"
```

A counter is readable as a variable only when no variable shadows it.

### cycle

```liquid
{% cycle 'odd', 'even' %}
{% cycle group: 'a', 'b' %}
```

Without a named group, the argument list itself identifies the cycle. The
position belongs to the group but the values come from the current call.

```jldoctest
julia> using Liquid

julia> render("{% for i in (1..4) %}{% cycle 'odd', 'even' %} {% endfor %}")
"odd even odd even "
```

### Literal and comments

```liquid
{% raw %}{{ not a variable }}{% endraw %}
{% comment %}anything, even {% broken %}{% endcomment %}
```

A `comment` body is skipped without being parsed, so commenting out a broken
block works. It is still *lexed*, so an unterminated `{{` inside one is still a
syntax error.

### echo

`{% echo x | upcase %}` is the tag form of `{{ }}`. Unlike `{{ }}`, an empty
`{% echo %}` is legal and renders nothing.

## Filters

Applied left to right with `|`, arguments after `:` separated by commas.

**Numbers.** `abs`, `at_least`, `at_most`, `ceil`, `divided_by`, `floor`,
`minus`, `modulo`, `plus`, `round`, `times`.

Non-numeric operands count as 0, so these do not fail — except `divided_by` and
`modulo`, which reject a zero or non-numeric divisor. Division of two integers
is **integer division**:

```jldoctest
julia> using Liquid

julia> render("{{ 9 | divided_by: 2 }} {{ 9.0 | divided_by: 2 }}")
"4 4.5"
```

**Strings.** `append`, `capitalize`, `downcase`, `lstrip`, `newline_to_br`,
`prepend`, `remove`, `remove_first`, `replace`, `replace_first`, `rstrip`,
`slice`, `split`, `strip`, `strip_html`, `strip_newlines`, `truncate`,
`truncatewords`, `upcase`, `url_decode`, `url_encode`, `escape`, `escape_once`.

`truncate` counts the ellipsis in its length. A `split` separator of a single
space splits on any run of whitespace, as in Ruby.

**Arrays.** `compact`, `concat`, `first`, `join`, `last`, `map`, `reverse`,
`size`, `sort`, `sort_natural`, `uniq`, `where`.

`join`, `concat` and `map` flatten nested arrays. `sort` orders by type and then
value and refuses values it cannot order; `sort_natural` compares the **printed
form**, case-insensitively, so numbers sort as text.

**Other.** `default`, `date`.

`default` substitutes when the input is blank — nil, `false`, an empty string,
array or hash. Zero is *not* blank. Pass `allow_false: true` to let an explicit
`false` through.

`date` takes Ruby strftime codes, not Julia's `Dates` formats. The input may be
a `DateTime`, a Unix timestamp, `"now"`, or a date string.

```jldoctest
julia> using Liquid

julia> render("{{ 'March 14, 2016' | date: '%b %d, %Y' }}")
"Mar 14, 2016"

julia> render("{{ 1152098955 | date: '%m/%d/%Y' }}")
"07/05/2006"
```

`%%` is a literal percent, and `-` between the `%` and the code drops zero
padding, as in `%-d`.
