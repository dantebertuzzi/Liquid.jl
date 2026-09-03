using Liquid: TEXT, OUTPUT, TAG, Token, tokenize, apply_whitespace_control,
              tag_args, LiquidSyntaxError

# Convenience: tokenize and describe each token as (kind, value, name).
shape(src) = [(t.kind, t.value, t.name) for t in tokenize(src)]

# Tokenize and apply whitespace control, the way the parser will consume it.
lex(src) = apply_whitespace_control(tokenize(src))
texts(src) = [t.value for t in lex(src)]

@testset "lexer" begin
    @testset "plain text" begin
        @test shape("") == []
        @test shape("hello") == [(TEXT, "hello", "")]
        @test shape("a\nb") == [(TEXT, "a\nb", "")]
        # A brace that does not open a delimiter stays literal.
        @test shape("{ not a tag }") == [(TEXT, "{ not a tag }", "")]
        @test shape("100% sure") == [(TEXT, "100% sure", "")]
        @test shape("trailing {") == [(TEXT, "trailing {", "")]
    end

    @testset "output statements" begin
        @test shape("{{ x }}") == [(OUTPUT, "x", "")]
        @test shape("{{x}}") == [(OUTPUT, "x", "")]
        @test shape("{{  a.b[0]  }}") == [(OUTPUT, "a.b[0]", "")]
        @test shape("{{ }}") == [(OUTPUT, "", "")]
        @test shape("a{{ x }}b") == [(TEXT, "a", ""), (OUTPUT, "x", ""), (TEXT, "b", "")]
        @test shape("{{ x }}{{ y }}") == [(OUTPUT, "x", ""), (OUTPUT, "y", "")]
        # Multi-line output; the value keeps its interior newline.
        @test shape("{{\n  x\n}}") == [(OUTPUT, "x", "")]
    end

    @testset "tags" begin
        @test shape("{% if x %}") == [(TAG, "if x", "if")]
        @test shape("{%if x%}") == [(TAG, "if x", "if")]
        @test shape("{% endif %}") == [(TAG, "endif", "endif")]
        @test shape("{% assign a = 1 %}") == [(TAG, "assign a = 1", "assign")]
        @test shape("{% cycle 'a', 'b' %}") == [(TAG, "cycle 'a', 'b'", "cycle")]
        # A tag body that is not an identifier yields no name; the parser rejects it.
        @test shape("{% 123 %}") == [(TAG, "123", "")]
        @test shape("{% %}") == [(TAG, "", "")]
    end

    @testset "tag_args" begin
        args(src) = tag_args(only(tokenize(src)))
        @test args("{% if x > 1 %}") == ("x > 1", 1, 7)
        @test args("{% endif %}") == ("", 1, 9)
        @test args("{% assign  a = 1 %}") == ("a = 1", 1, 12)
    end

    @testset "delimiters inside string literals" begin
        # The closing delimiter must not be found inside a quoted string.
        @test shape("{{ '}}' }}") == [(OUTPUT, "'}}'", "")]
        @test shape("{{ '{{' }}") == [(OUTPUT, "'{{'", "")]
        @test shape("{% assign x = \"a%}b\" %}") == [(TAG, "assign x = \"a%}b\"", "assign")]
        @test shape("{{ \"it's\" }}") == [(OUTPUT, "\"it's\"", "")]
    end

    @testset "positions" begin
        # line and col point at the first character of the token value.
        toks = tokenize("hello\n{{ name }}\n{% if x %}")
        @test [(t.line, t.col) for t in toks] == [(1, 1), (2, 4), (2, 11), (3, 4)]

        # A value that starts on a later line than its delimiter.
        tok = only(tokenize("{{\n   x }}"))
        @test (tok.line, tok.col) == (2, 4)
    end

    @testset "whitespace control markers" begin
        tok = only(tokenize("{{- x -}}"))
        @test (tok.trim_left, tok.trim_right, tok.value) == (true, true, "x")

        tok = only(tokenize("{%- if x %}"))
        @test (tok.trim_left, tok.trim_right, tok.value) == (true, false, "if x")

        # Degenerate forms still parse to an empty value.
        @test only(tokenize("{{- -}}")).value == ""
        @test only(tokenize("{{-}}")).value == ""
    end

    @testset "whitespace control application" begin
        @test texts("a  {{- x }}  b") == ["a", "x", "  b"]
        @test texts("a  {{ x -}}  b") == ["a  ", "x", "b"]
        @test texts("a  {{- x -}}  b") == ["a", "x", "b"]
        @test texts("a  {{ x }}  b") == ["a  ", "x", "  b"]
        # Trimming crosses newlines, not just to the line boundary.
        @test texts("a\n\n  {%- if x %}") == ["a", "if x"]
        # A text token emptied by trimming is dropped entirely.
        @test texts("  {{- x -}}  ") == ["x"]
        @test texts("{% if x -%}\n  body\n{%- endif %}") == ["if x", "body", "endif"]
    end

    @testset "raw" begin
        # The body is literal text, even when it contains delimiters.
        @test shape("{% raw %}{{ x }}{% endraw %}") == [(TEXT, "{{ x }}", "")]
        @test shape("{% raw %}{% if %}{% endraw %}") == [(TEXT, "{% if %}", "")]
        # An empty raw body still produces a token, because it may carry trim
        # markers for its neighbours; apply_whitespace_control drops it.
        @test shape("{% raw %}{% endraw %}") == [(TEXT, "", "")]
        @test texts("{% raw %}{% endraw %}") == []
        @test texts("x  {%- raw %}{% endraw %}  y") == ["x", "  y"]
        @test shape("a{% raw %}b{% endraw %}c") ==
              [(TEXT, "a", ""), (TEXT, "b", ""), (TEXT, "c", "")]

        # Inner markers trim the raw body; outer markers trim the neighbours.
        @test texts("x  {%- raw %}  b  {% endraw %}") == ["x", "  b  "]
        @test texts("x  {% raw -%}  b  {% endraw %}") == ["x  ", "b  "]
        @test texts("{% raw %}  b  {%- endraw %}  y") == ["  b", "  y"]
        @test texts("{% raw %}  b  {% endraw -%}  y") == ["  b  ", "y"]

        @test_throws LiquidSyntaxError tokenize("{% raw %}no end")
        @test_throws LiquidSyntaxError tokenize("{% raw foo %}{% endraw %}")
    end

    @testset "syntax errors" begin
        err = try
            tokenize("hello\n{{ x ")
            nothing
        catch e
            e
        end
        @test err isa LiquidSyntaxError
        @test err.line == 2 && err.col == 1
        @test occursin("unclosed output statement", sprint(showerror, err))

        @test_throws LiquidSyntaxError tokenize("{% if x ")
        @test_throws LiquidSyntaxError tokenize("{{ 'abc }}")

        err = try
            tokenize("{{ 'abc }}")
            nothing
        catch e
            e
        end
        @test occursin("unterminated string literal", sprint(showerror, err))
    end

    @testset "unicode" begin
        # Positions are counted in characters, not bytes.
        toks = tokenize("olá {{ nome }}")
        @test toks[2].col == 8
        @test shape("{{ 'ção' }}") == [(OUTPUT, "'ção'", "")]
        @test texts("é  {{- x }}") == ["é", "x"]
    end
end
