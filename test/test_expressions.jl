using Liquid: Expression, LiteralExpr, VariableExpr, RangeExpr, CompareExpr,
              BooleanExpr, NotExpr, FilterCall, FilteredExpr,
              EQ, NE, GT, LT, GE, LE, CONTAINS, EMPTY, BLANK,
              parse_value, parse_condition, parse_filtered, LiquidSyntaxError

value(src) = parse_value(src, 1, 1)
cond(src) = parse_condition(src, 1, 1)
filtered(src) = parse_filtered(src, 1, 1)

@testset "expression parser" begin
    @testset "literals" begin
        @test value("'hi'") == lit("hi")
        @test value("42") == lit(42)
        @test value("-42") == lit(-42)
        @test value("3.5") == lit(3.5)
        @test value("true") == lit(true)
        @test value("false") == lit(false)
        @test value("nil") == lit(nothing)
        @test value("null") == lit(nothing)
        @test value("empty") == lit(EMPTY)
        @test value("blank") == lit(BLANK)
        # Integers and floats stay distinct: Liquid's arithmetic depends on it.
        @test value("42").value isa Int
        @test value("42.0").value isa Float64
    end

    @testset "variables and paths" begin
        @test value("foo") == var("foo")
        @test value("some-thing") == var("some-thing")
        # A trailing `?` is part of the identifier, inherited from Ruby.
        @test value("bar?") == var("bar?")
        @test value("x?") == var("x?")
        @test value("foo.bar") == var("foo", "bar")
        @test value("foo.bar.baz") == var("foo", "bar", "baz")
        @test value("a[0]") == VariableExpr(Expression[lit("a"), lit(0)], 1, 1)
        @test value("a['k']") == VariableExpr(Expression[lit("a"), lit("k")], 1, 1)
        # A subscript root, the only way to name a key that is not an identifier.
        @test value("[\"a b\"]") == VariableExpr(Expression[lit("a b")], 1, 1)
        # A computed subscript nests a variable inside the path.
        @test value("a[b]") == VariableExpr(Expression[lit("a"), var("b")], 1, 1)
        @test value("a.b[0].c") ==
              VariableExpr(Expression[lit("a"), lit("b"), lit(0), lit("c")], 1, 1)
    end

    @testset "keywords are literals only without a path" begin
        # Bare, they are literals.
        @test value("nil") == lit(nothing)
        @test value("blank") == lit(BLANK)
        @test value("empty") == lit(EMPTY)
        @test value("true") == lit(true)

        # Followed by a path they are ordinary lookups of a variable that
        # happens to share the name.  The reference suite renders
        # `{{ blank.a }}` as 42 given data {"blank": {"a": 42}}.
        @test value("blank.a") == var("blank", "a")
        @test value("blank['a']") == var("blank", "a")
        @test value("empty.b") == var("empty", "b")
        @test value("nil.x.y") == var("nil", "x", "y")
        @test value("false.x") == var("false", "x")
        @test value("true['x']") == var("true", "x")
    end

    @testset "ranges" begin
        @test value("(1..5)") == RangeExpr(lit(1), lit(5))
        @test value("(a..b)") == RangeExpr(var("a"), var("b"))
        @test value("(1.4..5)") == RangeExpr(lit(1.4), lit(5))
    end

    @testset "comparisons" begin
        @test cond("a == b") == CompareExpr(EQ, var("a"), var("b"))
        @test cond("a != b") == CompareExpr(NE, var("a"), var("b"))
        # `<>` is an accepted alias of `!=`.
        @test cond("a <> b") == CompareExpr(NE, var("a"), var("b"))
        @test cond("a > 1") == CompareExpr(GT, var("a"), lit(1))
        @test cond("a < 1") == CompareExpr(LT, var("a"), lit(1))
        @test cond("a >= 1") == CompareExpr(GE, var("a"), lit(1))
        @test cond("a <= 1") == CompareExpr(LE, var("a"), lit(1))
        @test cond("a contains 'x'") == CompareExpr(CONTAINS, var("a"), lit("x"))
        # A bare value is a valid condition, tested for truthiness.
        @test cond("a") == var("a")
        @test cond("a.b") == var("a", "b")
    end

    @testset "and/or associate to the right with one precedence" begin
        @test cond("a and b") == BooleanExpr(:and, var("a"), var("b"))
        @test cond("a or b") == BooleanExpr(:or, var("a"), var("b"))

        # The case that separates Liquid from every language where `and` binds
        # tighter than `or`.  Reference suite: this template renders "".
        tree = cond("true and false and false or true")
        @test tree == BooleanExpr(:and, lit(true),
                        BooleanExpr(:and, lit(false),
                          BooleanExpr(:or, lit(false), lit(true))))

        # A minimal evaluator, to show the shape really yields false.  The real
        # renderer comes later; this only checks the tree we just built.
        eval_bool(e::LiteralExpr) = e.value === true
        eval_bool(e::BooleanExpr) = e.op === :and ?
            (eval_bool(e.left) && eval_bool(e.right)) :
            (eval_bool(e.left) || eval_bool(e.right))

        @test eval_bool(tree) == false
        # Julia's own precedence would disagree, which is the whole point.
        @test ((true && false && false) || true) == true

        # Comparisons bind tighter than the connectives.
        @test cond("a == 1 and b == 2") ==
              BooleanExpr(:and, CompareExpr(EQ, var("a"), lit(1)),
                                CompareExpr(EQ, var("b"), lit(2)))
    end

    @testset "filters" begin
        @test filtered("x") == FilteredExpr(var("x"), FilterCall[])
        @test filtered("x | upcase") ==
              FilteredExpr(var("x"), [FilterCall("upcase", Expression[], Pair{String,Expression}[], 1, 1)])
        @test filtered("x | join: ', '") ==
              FilteredExpr(var("x"), [FilterCall("join", Expression[lit(", ")], Pair{String,Expression}[], 1, 1)])
        @test filtered("x | slice: 1, 3") ==
              FilteredExpr(var("x"), [FilterCall("slice", Expression[lit(1), lit(3)], Pair{String,Expression}[], 1, 1)])

        # Chained filters keep their order.
        chain = filtered("x | downcase | truncate: 5")
        @test [f.name for f in chain.filters] == ["downcase", "truncate"]

        # Keyword arguments, and the interleaving the reference suite exercises.
        f = only(filtered("false | default: 'bar', allow_false: true").filters)
        @test f.args == Expression[lit("bar")]
        @test f.kwargs == ["allow_false" => lit(true)]

        f = only(filtered("false | default: allow_false: false, 'bar'").filters)
        @test f.args == Expression[lit("bar")]
        @test f.kwargs == ["allow_false" => lit(false)]

        @test filtered("(1..5) | join: '#'").expr == RangeExpr(lit(1), lit(5))
    end

    @testset "syntax errors" begin
        @test_throws LiquidSyntaxError filtered("")
        @test_throws LiquidSyntaxError cond("")
        @test_throws LiquidSyntaxError value("a b")          # trailing junk
        @test_throws LiquidSyntaxError value("a.")           # no property name
        @test_throws LiquidSyntaxError value("a.1")          # property must be a name
        @test_throws LiquidSyntaxError value("a[0")          # unclosed subscript
        @test_throws LiquidSyntaxError value("(1..5")        # unclosed range
        @test_throws LiquidSyntaxError value("(1)")          # a paren group is not a range
        @test_throws LiquidSyntaxError filtered("x |")       # no filter name
        @test_throws LiquidSyntaxError filtered("x | ,")     # no filter name
        @test_throws LiquidSyntaxError cond("a and")         # dangling connective
        @test_throws LiquidSyntaxError cond("a ==")          # dangling operator

        # Errors carry the position of the offending token, offset correctly.
        err = try
            parse_value("a b", 3, 10)
            nothing
        catch e
            e
        end
        @test (err.line, err.col) == (3, 12)
    end
end
