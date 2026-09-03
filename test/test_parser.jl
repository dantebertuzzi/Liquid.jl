using Liquid: Node, TextNode, OutputNode, ConditionalBranch, IfNode, ForNode,
              BreakNode, ContinueNode,
              Expression, LiteralExpr, VariableExpr, RangeExpr, CompareExpr,
              BooleanExpr, FilterCall, FilteredExpr, EQ, GT,
              TagDef, Parser, Token, TAG, parse_nodes, parse_block!,
              default_tags, register_tag!, tag_args, syntax_error,
              LiquidSyntaxError

parse_src(src) = parse_nodes(src, default_tags())

@testset "parser" begin
    @testset "text and output" begin
        @test parse_src("") == Node[]
        @test parse_src("hello") == [TextNode("hello")]
        @test parse_src("{{ x }}") == [out(var("x"))]
        @test parse_src("a{{ x }}b") == [TextNode("a"), out(var("x")), TextNode("b")]
        @test parse_src("{{ x | upcase }}") ==
              [OutputNode(FilteredExpr(var("x"),
                  [FilterCall("upcase", Expression[], Pair{String,Expression}[], 1, 1)]), 1)]
        # raw arrives from the lexer as plain text
        @test parse_src("{% raw %}{{ x }}{% endraw %}") == [TextNode("{{ x }}")]
    end

    @testset "if" begin
        @test parse_src("{% if a %}y{% endif %}") ==
              [IfNode([ConditionalBranch(var("a"), [TextNode("y")])], Node[], 1)]

        @test parse_src("{% if a %}y{% else %}n{% endif %}") ==
              [IfNode([ConditionalBranch(var("a"), [TextNode("y")])], [TextNode("n")], 1)]

        node = only(parse_src("{% if a %}1{% elsif b %}2{% elsif c %}3{% else %}4{% endif %}"))
        @test [b.condition for b in node.branches] == [var("a"), var("b"), var("c")]
        @test [b.body for b in node.branches] ==
              [[TextNode("1")], [TextNode("2")], [TextNode("3")]]
        @test node.else_body == [TextNode("4")]

        # Conditions are full expressions, with Liquid's own precedence.
        node = only(parse_src("{% if a == 1 and b %}y{% endif %}"))
        @test node.branches[1].condition ==
              BooleanExpr(:and, CompareExpr(EQ, var("a"), lit(1)), var("b"))

        # Nesting.
        node = only(parse_src("{% if a %}{% if b %}x{% endif %}{% endif %}"))
        @test only(node.branches[1].body) isa IfNode

        # An empty body is legal.
        @test only(parse_src("{% if a %}{% endif %}")).branches[1].body == Node[]
    end

    @testset "the first else wins" begin
        # Shopify parses arms after the first `{% else %}` but never renders
        # them; both of these render "2".
        node = only(parse_src("{% if a %}1{% else %}2{% else %}3{% endif %}"))
        @test node.else_body == [TextNode("2")]
        @test length(node.branches) == 1

        node = only(parse_src("{% if a %}1{% else %}2{% elsif b %}3{% endif %}"))
        @test node.else_body == [TextNode("2")]
        @test length(node.branches) == 1

        # An empty first else body still shadows a later one.
        node = only(parse_src("{% if a %}1{% else %}{% else %}3{% endif %}"))
        @test node.else_body == Node[]

        # A discarded arm must still be syntactically valid.
        @test_throws LiquidSyntaxError parse_src("{% if a %}1{% else %}2{% elsif %}3{% endif %}")
    end

    @testset "break and continue" begin
        node = only(parse_src("{% for i in xs %}{% break %}{% endfor %}"))
        @test node.body == [BreakNode(1)]
        node = only(parse_src("{% for i in xs %}{% continue %}{% endfor %}"))
        @test node.body == [ContinueNode(1)]
        # Legal outside a loop too; it is a no-op at render time.
        @test parse_src("{% break %}") == [BreakNode(1)]
        @test_throws LiquidSyntaxError parse_src("{% break now %}")
    end

    @testset "for" begin
        node = only(parse_src("{% for i in xs %}{{ i }}{% endfor %}"))
        @test node.varname == "i"
        @test node.iterable == var("xs")
        @test node.body == [out(var("i"))]
        @test node.else_body == Node[]
        @test node.limit === nothing && node.offset === nothing && node.reversed == false

        @test only(parse_src("{% for i in (1..5) %}x{% endfor %}")).iterable ==
              RangeExpr(lit(1), lit(5))

        # Modifiers, in any order, with or without commas.
        node = only(parse_src("{% for i in xs limit: 2 offset: 1 reversed %}x{% endfor %}"))
        @test (node.limit, node.offset, node.reversed) == (lit(2), lit(1), true)

        node = only(parse_src("{% for i in xs reversed, limit: 2 %}x{% endfor %}"))
        @test (node.limit, node.reversed) == (lit(2), true)

        # limit and offset may be variables, so they stay expressions.
        @test only(parse_src("{% for i in xs limit: n %}x{% endfor %}")).limit == var("n")

        # for/else
        node = only(parse_src("{% for i in xs %}a{% else %}b{% endfor %}"))
        @test node.body == [TextNode("a")] && node.else_body == [TextNode("b")]

        # Hyphenated loop variables are valid identifiers.
        @test only(parse_src("{% for x-y in xs %}z{% endfor %}")).varname == "x-y"
    end

    @testset "whitespace control reaches the parser" begin
        @test parse_src("a  {%- if x -%}  b  {%- endif %}") ==
              [TextNode("a"), IfNode([ConditionalBranch(var("x"), [TextNode("b")])], Node[], 1)]
    end

    @testset "syntax errors" begin
        @test_throws LiquidSyntaxError parse_src("{% if a %}")           # unclosed block
        @test_throws LiquidSyntaxError parse_src("{% for i in xs %}")    # unclosed block
        @test_throws LiquidSyntaxError parse_src("{% if %}x{% endif %}") # no condition
        @test_throws LiquidSyntaxError parse_src("{% endif %}")          # stray inner tag
        @test_throws LiquidSyntaxError parse_src("{% else %}")           # stray inner tag
        @test_throws LiquidSyntaxError parse_src("{% nope %}")           # unknown tag
        @test_throws LiquidSyntaxError parse_src("{{ }}")                # empty output
        @test_throws LiquidSyntaxError parse_src("{% for i xs %}x{% endfor %}")     # missing 'in'
        @test_throws LiquidSyntaxError parse_src("{% for i in xs nope: 1 %}x{% endfor %}")

        # A stray closing tag is reported as unexpected, not unknown.
        err = try; parse_src("{% endif %}"); nothing; catch e; e; end
        @test occursin("unexpected tag 'endif'", sprint(showerror, err))

        err = try; parse_src("{% nope %}"); nothing; catch e; e; end
        @test occursin("unknown tag 'nope'", sprint(showerror, err))

        # Positions survive into the parser.
        err = try; parse_src("hello\n{% if %}x{% endif %}"); nothing; catch e; e; end
        @test (err.line, err.col) == (2, 4)
    end

    @testset "tags are registrable without touching the package" begin
        # A user-defined block tag: {% shout %}...{% endshout %}
        struct ShoutNode <: Node
            body::Vector{Node}
        end

        function parse_shout(p::Parser, tok::Token)
            body, _ = parse_block!(p, ["endshout"])
            return ShoutNode(body)
        end

        tags = default_tags()
        register_tag!(tags, TagDef("shout", parse_shout; inner = ["endshout"]))

        nodes = parse_nodes("{% shout %}hi {{ x }}{% endshout %}", tags)
        node = only(nodes)
        @test node isa ShoutNode
        @test node.body == [TextNode("hi "), out(var("x"))]

        # The registry is per-call, so the default one is untouched.
        @test_throws LiquidSyntaxError parse_nodes("{% shout %}x{% endshout %}", default_tags())

        # And the stray-inner-tag message works for user tags too.
        err = try; parse_nodes("{% endshout %}", tags); nothing; catch e; e; end
        @test occursin("unexpected tag 'endshout'", sprint(showerror, err))
    end
end
