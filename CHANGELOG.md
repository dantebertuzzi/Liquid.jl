# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

First release in preparation. Nothing has been tagged yet.

### Added

- Three-stage engine, each stage usable and testable on its own: a lexer
  producing tokens, a parser producing an AST of `Node`s, and an interpreting
  renderer that walks the AST against a context.
- Tags: `assign`, `capture`, `if`/`elsif`/`else`, `unless`, `case`/`when`,
  `for` (with `limit`, `offset`, `offset: continue`, `reversed`, `else`,
  `break`, `continue`), `cycle`, `increment`, `decrement`, `raw`, `comment`
  and `echo`.
- The standard filter set: `abs`, `append`, `at_least`, `at_most`,
  `capitalize`, `ceil`, `compact`, `concat`, `date`, `default`, `divided_by`,
  `downcase`, `escape`, `escape_once`, `first`, `floor`, `join`, `last`,
  `lstrip`, `map`, `minus`, `modulo`, `newline_to_br`, `plus`, `prepend`,
  `remove`, `remove_first`, `replace`, `replace_first`, `reverse`, `round`,
  `rstrip`, `size`, `slice`, `sort`, `sort_natural`, `split`, `strip`,
  `strip_html`, `strip_newlines`, `times`, `truncate`, `truncatewords`,
  `uniq`, `upcase`, `url_decode`, `url_encode` and `where`.
- Expressions with Liquid's own semantics, including `and` and `or` sharing one
  precedence level and associating to the right.
- Registrable tags and filters, held per `Environment` so that registering into
  one environment never affects another.
- The `liquid_properties` / `liquid_get` interface, and the `@liquid_drop`
  macro, by which a user's type chooses which of its fields templates may read.
  Types are opaque by default.
- `date` filter using Ruby strftime codes, translated explicitly rather than
  mapped onto Julia's `Dates` format strings.
- `FileSystemLoader`, which refuses a template name that resolves outside its
  root.
- `autoescape`, `strict_variables` and `strict_filters` options.
- Documentation built with Documenter, with doctested examples.

### Conformance

Validated against the [Golden Liquid](https://github.com/jg-rp/golden-liquid)
suite at commit `65c2f76`, vendored under `test/golden/`.

    862 / 865 in-scope cases pass (99.7%)

233 of the suite's 1098 cases exercise features outside this scope and are
skipped rather than counted. Of the three remaining, two are cases the suite
contradicts itself on, marking the same template valid under one strictness
mode and invalid under another; the third asks that slicing a range use the
range's string representation.

### Security

Rendering a template never evaluates Julia code. There is no `eval`, no
`getproperty` and no reflection on the render path; a test asserts this against
the package source itself, so the invariant fails loudly if it is ever broken.
