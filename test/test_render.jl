using Liquid: render, parse_template, Environment, LiquidUndefinedError,
              LiquidArgumentError

@testset "render" begin
    @testset "data shapes" begin
        @test render("{{ x }}"; x = 1) == "1"
        @test render("{{ x }}", (x = 1,)) == "1"
        @test render("{{ x }}", Dict("x" => 1)) == "1"
        @test render("{{ x }}", Dict(:x => 1)) == "1"
        @test render("hello") == "hello"
    end

    @testset "a parsed template renders many times" begin
        tmpl = parse_template("Hello, {{ name }}!")
        @test render(tmpl; name = "World") == "Hello, World!"
        @test render(tmpl; name = "Liquid") == "Hello, Liquid!"
    end

    @testset "undefined variables render empty" begin
        @test render("[{{ nope }}]") == "[]"
        @test render("[{{ a.b.c }}]") == "[]"
        @test render("[{{ a.b.c }}]"; a = 1) == "[]"
        @test render("[{{ nope[0] }}]") == "[]"
        # Leniency is the point: none of these raise.
        @test render("[{{ nope | nosuchfilter }}]") == "[]"
    end

    @testset "strict_variables is opt-in" begin
        env = Environment(strict_variables = true)
        @test_throws LiquidUndefinedError render(parse_template("{{ nope }}"; env), nothing)
        @test render(parse_template("{{ x }}"; env), Dict("x" => 1)) == "1"
        err = try
            render(parse_template("{{ a.b }}"; env), nothing)
            nothing
        catch e
            e
        end
        @test occursin("a.b", sprint(showerror, err))
    end

    @testset "lookups" begin
        data = Dict("a" => Dict("b" => Dict("c" => 42)))
        @test render("{{ a.b.c }}", data) == "42"
        @test render("{{ a['b']['c'] }}", data) == "42"
        # Subscripts are 0-based.
        @test render("{{ xs[0] }}-{{ xs[2] }}", Dict("xs" => [10, 20, 30])) == "10-30"
        @test render("[{{ xs[9] }}]", Dict("xs" => [1])) == "[]"
        # A computed subscript.
        @test render("{{ xs[i] }}", Dict("xs" => [10, 20], "i" => 1)) == "20"
        # A key that is not an identifier needs the subscript root form.
        @test render("{{ [\"a b\"] }}", Dict("a b" => "ok")) == "ok"
    end

    @testset "virtual properties" begin
        @test render("{{ s.size }}", Dict("s" => "hello")) == "5"
        @test render("{{ s.first }}{{ s.last }}", Dict("s" => "hello")) == "ho"
        @test render("{{ a.size }}", Dict("a" => [3, 2, 1])) == "3"
        @test render("{{ a.first }}{{ a.last }}", Dict("a" => [3, 2, 1])) == "31"
        # A real key shadows the virtual property.
        @test render("{{ o.first }}", Dict("o" => Dict("a" => 1, "first" => 99))) == "99"
        @test render("{{ o.size }}", Dict("o" => Dict("size" => 99))) == "99"
        # A mapping has no virtual `last`.
        @test render("[{{ o.last }}]", Dict("o" => Dict("a" => 1))) == "[]"
    end

    @testset "if" begin
        @test render("{% if x %}y{% else %}n{% endif %}"; x = true) == "y"
        @test render("{% if x %}y{% else %}n{% endif %}"; x = false) == "n"
        @test render("{% if x %}y{% else %}n{% endif %}") == "n"
        # 0 and "" are truthy.
        @test render("{% if x %}y{% else %}n{% endif %}"; x = 0) == "y"
        @test render("{% if x %}y{% else %}n{% endif %}"; x = "") == "y"
        @test render("{% if a %}1{% elsif b %}2{% else %}3{% endif %}"; a = false, b = true) == "2"
        @test render("{% if a > 1 %}y{% endif %}"; a = 2) == "y"
        @test render("{% if a contains 'b' %}y{% endif %}"; a = "abc") == "y"

        # The precedence rule, end to end: this renders nothing.
        @test render("{% if true and false and false or true %}hello{% endif %}") == ""
        # The first else wins.
        @test render("{% if false %}1{% else %}2{% else %}3{% endif %}") == "2"
    end

    @testset "order comparison raises on mixed types" begin
        @test_throws LiquidArgumentError render("{% if '2' > 1 %}y{% endif %}")
        @test render("{% if 'abc' < 'acb' %}y{% else %}n{% endif %}") == "y"
        # Against empty/blank it is false, not an error.
        @test render("{% if blank <= 1 or blank >= 1 %}T{% else %}F{% endif %}") == "F"
    end

    @testset "for" begin
        @test render("{% for i in xs %}{{ i }}{% endfor %}"; xs = [1, 2, 3]) == "123"
        @test render("{% for i in (1..4) %}{{ i }}{% endfor %}") == "1234"
        # A float range endpoint is truncated.
        @test render("{% for i in (1.4..4) %}{{ i }}{% endfor %}") == "1234"
        @test render("{% for i in xs %}{{ i }}{% else %}none{% endfor %}"; xs = []) == "none"
        @test render("{% for i in xs %}{{ i }}{% else %}none{% endfor %}") == "none"

        # Modifiers slice before `reversed` flips.
        @test render("{% for i in (1..6) limit: 2 %}{{ i }}{% endfor %}") == "12"
        @test render("{% for i in (1..6) offset: 4 %}{{ i }}{% endfor %}") == "56"
        @test render("{% for i in (1..6) limit: 2 offset: 1 %}{{ i }}{% endfor %}") == "23"
        @test render("{% for i in (1..3) reversed %}{{ i }}{% endfor %}") == "321"
        @test render("{% for i in (1..6) limit: 2 reversed %}{{ i }}{% endfor %}") == "21"
        # A modifier may be a variable.
        @test render("{% for i in (1..6) limit: n %}{{ i }}{% endfor %}"; n = 3) == "123"
        @test_throws LiquidArgumentError render("{% for i in (1..4) limit: 'foo' %}x{% endfor %}")

        # A mapping iterates as [key, value] pairs.
        @test render("{% for p in o %}{{ p[0] }}={{ p[1] }};{% endfor %}",
                     Dict("o" => Dict("a" => 1))) == "a=1;"
        # Anything not a collection iterates as nothing.
        @test render("{% for i in x %}y{% else %}none{% endfor %}"; x = 42) == "none"
        # A non-empty string is one item, not its characters.
        @test render("{% for i in x %}[{{ i }}]{% endfor %}"; x = "abc") == "[abc]"
        @test render("{% for i in x %}y{% else %}none{% endfor %}"; x = "") == "none"
    end

    @testset "forloop" begin
        t = "{% for i in (1..3) %}{{ forloop.index }}/{{ forloop.index0 }}/" *
            "{{ forloop.rindex }}/{{ forloop.rindex0 }} {% endfor %}"
        @test render(t) == "1/0/3/2 2/1/2/1 3/2/1/0 "
        @test render("{% for i in (1..3) %}{{ forloop.first }}{% endfor %}") == "truefalsefalse"
        @test render("{% for i in (1..3) %}{{ forloop.last }}{% endfor %}") == "falsefalsetrue"
        @test render("{% for i in (1..3) %}{{ forloop.length }}{% endfor %}") == "333"
        # first/last are relative to the slice, not the original collection.
        @test render("{% for i in (1..6) limit: 2 offset: 1 %}{{ forloop.first }},{% endfor %}") ==
              "true,false,"
        # An unknown property is nil, not an error.
        @test render("[{% for i in (1..1) %}{{ forloop.nope }}{% endfor %}]") == "[]"
        # parentloop, and its absence.
        @test render("{% for i in (1..2) %}{% for j in (1..2) %}{{ forloop.parentloop.index }}{% endfor %}{% endfor %}") ==
              "1122"
        @test render("[{% for i in (1..1) %}{{ forloop.parentloop.index }}{% endfor %}]") == "[]"
    end

    @testset "break and continue" begin
        @test render("{% for i in (1..5) %}{% if i == 3 %}{% break %}{% endif %}{{ i }}{% endfor %}") == "12"
        @test render("{% for i in (1..5) %}{% if i == 3 %}{% continue %}{% endif %}{{ i }}{% endfor %}") == "1245"
        # break only leaves the innermost loop.
        @test render("{% for i in (1..2) %}{% for j in (1..3) %}{% if j == 2 %}{% break %}{% endif %}{{ j }}{% endfor %}|{% endfor %}") ==
              "1|1|"
        # Outside a loop the interrupt reaches the top and stops rendering.
        # Not covered by the golden suite; this matches the reference engine.
        @test render("a{% break %}b") == "a"
    end

    @testset "scopes" begin
        # The loop variable does not leak out of the loop.
        @test render("{% for i in (1..2) %}{{ i }}{% endfor %}[{{ i }}]") == "12[]"
        # An outer variable is visible inside.
        @test render("{% for i in (1..2) %}{{ x }}{% endfor %}"; x = "a") == "aa"
        # An inner loop shadows the outer variable of the same name.
        @test render("{% for i in (1..2) %}{% for i in (5..5) %}{{ i }}{% endfor %}{{ i }}{% endfor %}") ==
              "5152"
    end

    @testset "autoescape" begin
        env = Environment(autoescape = true)
        tmpl = parse_template("{{ x }}"; env)
        @test render(tmpl; x = "<b>&</b>") == "&lt;b&gt;&amp;&lt;/b&gt;"
        @test render(tmpl; x = "it's \"quoted\"") == "it&#39;s &#34;quoted&#34;"
        # Off by default.
        @test render("{{ x }}"; x = "<b>") == "<b>"
        # Literal template text is never escaped.
        @test render(parse_template("<p>{{ x }}</p>"; env); x = "<") == "<p>&lt;</p>"
    end

    @testset "whitespace control end to end" begin
        @test render("a  {%- if true -%}  b  {%- endif -%}  c") == "abc"
        @test render("{% for i in (1..2) -%}\n  {{ i }}\n{%- endfor %}") == "12"
    end

    @testset "render to an IO" begin
        io = IOBuffer()
        render(io, parse_template("{{ x }}!"), Dict("x" => "hi"))
        @test String(take!(io)) == "hi!"
    end
end
