using Liquid: render, parse_template, LiquidSyntaxError, LiquidArgumentError

@testset "tags" begin
    @testset "assign" begin
        @test render("{% assign x = 5 %}{{ x }}") == "5"
        @test render("{% assign x = 'hi' %}{{ x }}") == "hi"
        @test render("{% assign x = y %}{{ x }}"; y = 7) == "7"
        @test render("{% assign x = a.b %}{{ x }}", Dict("a" => Dict("b" => 1))) == "1"
        # An assignment writes to the outermost scope, so it outlives the block.
        @test render("{% for i in (1..1) %}{% assign x = 9 %}{% endfor %}{{ x }}") == "9"
        @test render("{% if true %}{% assign x = 9 %}{% endif %}{{ x }}") == "9"
        # Reassignment.
        @test render("{% assign x = 1 %}{% assign x = 2 %}{{ x }}") == "2"
        # Generous names, read back by subscript when not an identifier.
        @test render("{% assign foo-a = 1 %}{{ foo-a }}") == "1"
        @test render("{% assign 123 = 'hi' %}{{ [\"123\"] }}") == "hi"
        @test render("{% assign _ = 'hi' %}{{ _ }}") == "hi"
        # But not these.
        @test_throws LiquidSyntaxError parse_template("{% assign -foo = 1 %}")
        @test_throws LiquidSyntaxError parse_template("{% assign foo? = 1 %}")
        @test_throws LiquidSyntaxError parse_template("{% assign x %}")
        @test_throws LiquidSyntaxError parse_template("{% assign x = %}")
    end

    @testset "capture" begin
        @test render("{% capture c %}hi{% endcapture %}[{{ c }}]") == "[hi]"
        @test render("{% capture c %}{{ x }}!{% endcapture %}{{ c }}"; x = "a") == "a!"
        # The body is not written out, only bound.
        @test render("[{% capture c %}hidden{% endcapture %}]") == "[]"
        @test render("{% capture c %}{% endcapture %}[{{ c }}]") == "[]"
        # Loops work inside a capture.
        @test render("{% capture c %}{% for i in (1..3) %}{{ i }}{% endfor %}{% endcapture %}{{ c }}") == "123"
        @test_throws LiquidSyntaxError parse_template("{% capture -c %}x{% endcapture %}")
        @test_throws LiquidSyntaxError parse_template("{% capture c %}x")
    end

    @testset "unless" begin
        @test render("{% unless false %}y{% endunless %}") == "y"
        @test render("{% unless true %}y{% endunless %}") == ""
        @test render("{% unless true %}a{% else %}b{% endunless %}") == "b"
        # Only the first condition is negated; elsif reads as written.
        @test render("{% unless true %}foo{% elsif true %}bar{% endunless %}") == "bar"
        @test render("{% unless true %}foo{% elsif false %}bar{% else %}hi{% endunless %}") == "hi"
        # 0 is truthy, so `unless 0` does not fire.
        @test render("{% unless 0 %}a{% else %}b{% endunless %}") == "b"
        @test render("{% unless 1 == true %}a{% else %}b{% endunless %}") == "a"
        # The first else wins here too.
        @test render("{% unless true %}1{% else %}2{% else %}3{% endunless %}") == "2"
        # Arguments on `else` are accepted and ignored.
        @test render("{% unless true %}1{% else nonsense %}2{% endunless %}") == "2"
        @test_throws LiquidSyntaxError parse_template("{% unless %}x{% endunless %}")
    end

    @testset "case" begin
        @test render("{% case x %}{% when 1 %}a{% when 2 %}b{% endcase %}"; x = 1) == "a"
        @test render("{% case x %}{% when 1 %}a{% when 2 %}b{% endcase %}"; x = 2) == "b"
        @test render("{% case x %}{% when 1 %}a{% else %}z{% endcase %}"; x = 9) == "z"
        @test render("{% case x %}{% when 1 %}a{% endcase %}"; x = 9) == ""
        # Several values per when, by comma or by `or`.
        @test render("{% case x %}{% when 1, 2 %}a{% endcase %}"; x = 2) == "a"
        @test render("{% case x %}{% when 1 or 2 %}a{% endcase %}"; x = 2) == "a"
        # Text before the first when is discarded.
        @test render("{% case x %}ignored{% when 1 %}a{% endcase %}"; x = 1) == "a"

        # Every matching when renders: the body repeats once per matching value.
        @test render("{% case x %}{% when 'b' or 'H', 'H' %}bar{% endcase %}"; x = "H") == "barbar"
        # And an else renders whenever nothing has matched *yet*, in source order.
        @test render("{% case 'x' %}{% when 'y' %}foo{% else %}bar{% when 'x' %}baz{% endcase %}") == "barbaz"
        @test render("{% case 'x' %}{% when 'y' %}f{% else %}b{% else %}z{% when 'x' %}q{% endcase %}") == "bzq"
        # An else after a match does not render.
        @test render("{% case 'x' %}{% when 'x' %}hit{% else %}miss{% endcase %}") == "hit"

        @test_throws LiquidSyntaxError parse_template("{% case %}{% when 1 %}a{% endcase %}")
        @test_throws LiquidSyntaxError parse_template("{% case x %}{% when %}a{% endcase %}")
    end

    @testset "cycle" begin
        @test render("{% cycle 1, 2, 3 %}{% cycle 1, 2, 3 %}{% cycle 1, 2, 3 %}") == "123"
        # It wraps around.
        @test render(repeat("{% cycle 'a', 'b' %}", 5)) == "ababa"
        # A different argument list is a different cycle.
        @test render("{% cycle '1','2','3' %}{% cycle '1','2' %}{% cycle '1','2','3' %}") == "112"
        # Spacing does not change the cycle's identity.
        @test render("{% cycle 1,2 %}{% cycle 1, 2 %}") == "12"
        # Named groups; the name is an expression, evaluated each time.
        @test render("{% cycle 'a': 1,2,3 %}{% cycle 'a': 7,8,9 %}{% cycle 'a': 1,2,3 %}") == "183"
        @test render("{% cycle g: 1,2,3 %}{% assign g = 'other' %}{% cycle g: 1,2,3 %}"; g = "one") == "11"
        # Two undefined group names are the same group.
        @test render("{% cycle a: 1,2,3 %}{% cycle b: 1,2,3 %}{% cycle 1,2,3 %}") == "121"

        # The position belongs to the group but the values come from this call,
        # so a position past the end of *this* list renders nothing.
        @test render("{% cycle a: '1','2' %}{% cycle a: '1','2','3' %}{% cycle a: '1' %}") == "12"
        @test render("{% cycle a: '1' %}{% cycle a: '1','2' %}{% cycle a: '1','2','3' %}") == "112"

        # Inside a loop, which is the usual use.
        @test render("{% for i in (1..4) %}{% cycle 'odd', 'even' %} {% endfor %}") ==
              "odd even odd even "
        @test_throws LiquidSyntaxError parse_template("{% cycle %}")
    end

    @testset "increment and decrement" begin
        @test render("{% increment f %}{% increment f %}{% increment f %}") == "012"
        @test render("{% decrement f %}{% decrement f %}") == "-1-2"
        # They share one counter, and the order of the two operations differs.
        @test render("{% decrement f %} {% decrement f %} {% increment f %}") == "-1 -2 -2"
        # Separate names, separate counters.
        @test render("{% increment a %}{% increment b %}{% increment a %}") == "001"
        # The counter namespace is separate from variables.
        @test render("{% assign f = 5 %}{{ f }} {% increment f %} {% increment f %} {{ f }}") ==
              "5 0 1 5"
        # But a counter is readable as a variable when nothing shadows it.
        @test render("{% increment f %} {{ f }}") == "0 1"
        @test render("{% decrement f %}{{ f }}") == "-1-1"
        @test_throws LiquidSyntaxError parse_template("{% increment %}")
    end

    @testset "echo" begin
        @test render("{% echo 42 %}") == "42"
        @test render("{% echo x %}"; x = "hi") == "hi"
        @test render("{% echo a.b %}", Dict("a" => Dict("b" => 1))) == "1"
        # Unlike `{{ }}`, an empty echo is legal.
        @test render("[{% echo %}]") == "[]"
        @test render("{% echo t[-2] %}", Dict("t" => ["a", "b"])) == "a"
    end

    @testset "comment" begin
        @test render("a{% comment %}hidden{% endcomment %}b") == "ab"
        # The body is skipped, not parsed: a broken block inside is fine.
        @test render("{% comment %}{% if true %}{% endcomment %}ok") == "ok"
        @test render("{% comment %}{% nosuchtag %}{% endcomment %}ok") == "ok"
        @test render("{% comment %}{{ ! }}{% endcomment %}ok") == "ok"
        # Nested comments are counted.
        @test render("{% comment %}{% comment %}{% endcomment %}{% endcomment %}ok") == "ok"
        @test render("{% comment %}a{% comment %}b{% endcomment %}c{% endcomment %}ok") == "ok"
        # But it is still lexed, so an unterminated delimiter is still an error.
        @test_throws LiquidSyntaxError parse_template("{% comment %}{{ {% endcomment %}")
        @test_throws LiquidSyntaxError parse_template("{% comment %}unclosed")
    end

    @testset "negative subscripts" begin
        data = Dict("t" => ["a", "b", "c"])
        @test render("{{ t[-1] }}", data) == "c"
        @test render("{{ t[-3] }}", data) == "a"
        @test render("[{{ t[-4] }}]", data) == "[]"
    end
end

@testset "blank block suppression" begin
    # A block whose body can only produce whitespace renders nothing at all.
    @test render("{% if true %}  {% endif %}") == ""
    @test render("{% unless false %}  {% endunless %}") == ""
    @test render("{% for i in (0..10) %}  {% endfor %}") == ""
    @test render("{% if true %}  {% elsif false %} {% else %} {% endif %}") == ""
    @test render("{% if true %} {% comment %}c{% endcomment %} {% endif %}") == ""
    # Tags that bind rather than write are blank too.
    @test render("!{% if true %}\n{% assign x = 1 %}\n{% endif %}!") == "!!"
    @test render("!{% if true %}\n{% capture c %}x{% endcapture %}\n{% endif %}!") == "!!"

    # The side effects still happen; only the whitespace is dropped.
    @test render("{% if true %}  {% assign x = 9 %}  {% endif %}{{ x }}") == "9"

    # An output statement is never blank, even when it renders empty.
    @test render("!{% if true %}\n{{ '' }}\n{% endif %}!") == "!\n\n!"
    # And blankness is decided by the whole tag: an arm that never runs counts.
    @test render("!{% if true %}\n{% assign x = 1 %}\n{% else %}\n{{ '' }}\n{% endif %}!") ==
          "!\n\n!"
    # Text that is not whitespace is of course kept.
    @test render("{% if true %} x {% endif %}") == " x "
end

@testset "for offset and limit" begin
    @test render("{% for i in (1..6) offset: 2 %}{{ i }}{% endfor %}") == "3456"
    @test render("{% for i in (1..6) limit: 2 offset: 1 %}{{ i }}{% endfor %}") == "23"

    # `offset: continue` resumes where the previous loop over the same
    # collection stopped; the loop's identity is variable-plus-collection.
    @test render("{% for i in (1..6) limit: 3 %}a{{ i }} {% endfor %}" *
                 "{% for i in (1..6) offset: continue %}b{{ i }} {% endfor %}") ==
          "a1 a2 a3 b4 b5 b6 "

    # A negative offset clamps where the slice starts but keeps its raw value
    # for the end of the slice and for the remembered position.
    @test render("{% for i in (0..3) offset: -2 %}a{{ i }} {% endfor %}") == "a0 a1 a2 a3 "
    @test render("{% for i in (0..3) offset: -2 limit: 3 %}{{ i }} {% endfor %}") == "0 "
    @test render("{% for i in (0..3) offset: -2 %}a{{ i }} {% endfor %}" *
                 "{% for i in (0..3) offset: continue %}b{{ i }} {% endfor %}") ==
          "a0 a1 a2 a3 b2 b3 "

    @test render("{% for i in (1..3) %}{{ forloop.name }}{% endfor %}") ==
          "i-(1..3)i-(1..3)i-(1..3)"
end

@testset "range bounds" begin
    # A literal float bound is truncated, but one arriving from a variable is
    # an error: a runtime bound has to already be whole.
    @test render("{% for i in (1.4..4) %}{{ i }}{% endfor %}") == "1234"
    @test_throws LiquidArgumentError render("{{ (x..5) | join: '#' }}"; x = 2.3)
    # A non-numeric bound counts as zero rather than raising.
    @test render("{{ (start..3) | join: '#' }}"; start = "foo") == "0#1#2#3"
    @test render("[{{ (5..1) | join: '#' }}]") == "[]"
end
