using Liquid: IDENT, STRING, NUMBER, OP, DOT, DOTDOT, LBRACKET, RBRACKET,
              LPAREN, RPAREN, PIPE, COLON, COMMA, ExprToken,
              tokenize_expression, LiquidSyntaxError

# Tokenize as if the content started at line 1, column 1.
kinds(src) = [(t.kind, t.value) for t in tokenize_expression(src, 1, 1)]

@testset "expression lexer" begin
    @testset "literals" begin
        @test kinds("'hello'") == [(STRING, "hello")]
        @test kinds("\"hello\"") == [(STRING, "hello")]
        @test kinds("''") == [(STRING, "")]
        # Quotes of the other kind are ordinary characters inside a string.
        @test kinds("\"it's\"") == [(STRING, "it's")]
        @test kinds("42") == [(NUMBER, "42")]
        @test kinds("-42") == [(NUMBER, "-42")]
        @test kinds("3.14") == [(NUMBER, "3.14")]
        @test kinds("-3.14") == [(NUMBER, "-3.14")]
    end

    @testset "identifiers" begin
        @test kinds("foo") == [(IDENT, "foo")]
        @test kinds("_foo9") == [(IDENT, "_foo9")]
        # Liquid identifiers may contain hyphens; `-` is never an operator.
        @test kinds("some-thing") == [(IDENT, "some-thing")]
        @test kinds("x-y") == [(IDENT, "x-y")]
        @test kinds("bar?") == [(IDENT, "bar?")]
        # Keywords are lexed as plain identifiers; the parser gives them meaning.
        @test kinds("true and nil") == [(IDENT, "true"), (IDENT, "and"), (IDENT, "nil")]
        @test kinds("contains") == [(IDENT, "contains")]
    end

    @testset "numbers versus ranges" begin
        # `.` only continues a number when a digit follows, so `..` survives.
        @test kinds("1..5") == [(NUMBER, "1"), (DOTDOT, ".."), (NUMBER, "5")]
        @test kinds("1.4..5") == [(NUMBER, "1.4"), (DOTDOT, ".."), (NUMBER, "5")]
        @test kinds("(1..5)") ==
              [(LPAREN, "("), (NUMBER, "1"), (DOTDOT, ".."), (NUMBER, "5"), (RPAREN, ")")]
    end

    @testset "operators" begin
        @test kinds("a == b") == [(IDENT, "a"), (OP, "=="), (IDENT, "b")]
        @test kinds("a != b") == [(IDENT, "a"), (OP, "!="), (IDENT, "b")]
        @test kinds("a <> b") == [(IDENT, "a"), (OP, "<>"), (IDENT, "b")]
        @test kinds("a >= b") == [(IDENT, "a"), (OP, ">="), (IDENT, "b")]
        @test kinds("a <= b") == [(IDENT, "a"), (OP, "<="), (IDENT, "b")]
        @test kinds("a > b") == [(IDENT, "a"), (OP, ">"), (IDENT, "b")]
        @test kinds("a < b") == [(IDENT, "a"), (OP, "<"), (IDENT, "b")]
    end

    @testset "paths and filters" begin
        @test kinds("a.b") == [(IDENT, "a"), (DOT, "."), (IDENT, "b")]
        @test kinds("a[0]") == [(IDENT, "a"), (LBRACKET, "["), (NUMBER, "0"), (RBRACKET, "]")]
        @test kinds("x | join: ', '") ==
              [(IDENT, "x"), (PIPE, "|"), (IDENT, "join"), (COLON, ":"), (STRING, ", ")]
        @test kinds("a, b") == [(IDENT, "a"), (COMMA, ","), (IDENT, "b")]
    end

    @testset "positions are absolute" begin
        # The body of `{{ x | upcase }}` starts at line 1, column 4.
        toks = tokenize_expression("x | upcase", 1, 4)
        @test [(t.line, t.col) for t in toks] == [(1, 4), (1, 6), (1, 8)]

        # A body spanning lines: only the first line is offset by the column.
        toks = tokenize_expression("a and\n  b", 3, 7)
        @test [(t.line, t.col) for t in toks] == [(3, 7), (3, 9), (4, 3)]
    end

    @testset "errors" begin
        @test_throws LiquidSyntaxError tokenize_expression("'abc", 1, 1)
        @test_throws LiquidSyntaxError tokenize_expression("a @ b", 1, 1)
        @test_throws LiquidSyntaxError tokenize_expression("a ! b", 1, 1)

        err = try
            tokenize_expression("x + y", 2, 5)
            nothing
        catch e
            e
        end
        @test err isa LiquidSyntaxError
        @test (err.line, err.col) == (2, 7)
    end
end
