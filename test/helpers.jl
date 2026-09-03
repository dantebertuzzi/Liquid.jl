# Shared shorthands for building expected ASTs in tests.

using Liquid: Expression, LiteralExpr, VariableExpr, FilterCall, FilteredExpr,
              OutputNode

"A literal expression."
lit(v) = LiteralExpr(v)

"""A dotted variable path: `var("a", "b")` is `a.b`.

Positions are not compared by `==`, so 1:1 is fine here."""
var(names...) = VariableExpr(Expression[LiteralExpr(n) for n in names], 1, 1)

"An output node with no filters."
out(e) = OutputNode(FilteredExpr(e, FilterCall[]), 1)
