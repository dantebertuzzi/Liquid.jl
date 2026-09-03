using Liquid: render, LiquidArgumentError

# Render an expression through the default environment.
f(src) = render("{{ " * src * " }}")

@testset "filters" begin
    @testset "arithmetic keeps Int and Float apart" begin
        @test f("10 | plus: 2") == "12"
        @test f("10 | plus: 2.0") == "12.0"
        @test f("10 | minus: 2") == "8"
        @test f("5 | times: 2") == "10"
        @test f("-5 | times: 2") == "-10"
        # Decimal arithmetic reads as decimal, not as binary float noise.
        @test f("10.1 | plus: 2.2") == "12.3"
        @test f("10.1 | minus: 2.2") == "7.9"
        @test f("10.1 | modulo: 7.0") == "3.1"
        # Non-numeric operands count as zero.
        @test f("'foo' | plus: 2") == "2"
        @test f("10 | plus: nosuchthing") == "10"
        @test f("'10.1' | plus: '2.2'") == "12.3"
    end

    @testset "divided_by is integer division for integers" begin
        @test f("9 | divided_by: 2") == "4"
        @test f("10 | divided_by: 2") == "5"
        @test f("9.0 | divided_by: 2") == "4.5"
        @test f("10 | divided_by: 2.0") == "5.0"
        @test f("20 | divided_by: 7.0") == "2.857142857142857"
        # Unlike the additive filters, a bad divisor is an error.
        @test_throws LiquidArgumentError render("{{ 10 | divided_by: 0 }}")
        @test_throws LiquidArgumentError render("{{ 10 | divided_by: 'foo' }}")
        @test_throws LiquidArgumentError render("{{ 10 | modulo: nosuchthing }}")
    end

    @testset "rounding" begin
        @test f("-5.4 | abs") == "5.4"
        @test f("'-5' | abs") == "5"
        @test f("'hello' | abs") == "0"
        @test f("5.4 | ceil") == "6"
        @test f("-5.4 | ceil") == "-5"
        @test f("5.4 | floor") == "5"
        @test f("-5.4 | floor") == "-6"
        @test f("5.6 | round") == "6"
        @test f("5.1 | round") == "5"
        @test f("5.666 | round: 1") == "5.7"
        @test f("5.666 | round: 0") == "6"
        @test f("5.666 | round: -2") == "0"
        # An integer input: `round(Int, ::Integer, ::RoundingMode)` has no
        # method before Julia 1.11, so this needs its own path.
        @test f("5 | round") == "5"
        @test f("-5 | round") == "-5"
        # Halves round away from zero, not to even as Julia does by default.
        @test f("2.5 | round") == "3"
        @test f("3.5 | round") == "4"
        @test f("5 | at_least: 8") == "8"
        @test f("8 | at_least: 5") == "8"
        @test f("5 | at_most: 8") == "5"
        @test f("'abc' | at_most: -2") == "-2"
    end

    @testset "strings" begin
        @test f("'hello' | append: 'there'") == "hellothere"
        @test f("'hello' | prepend: 'x'") == "xhello"
        @test f("5 | append: 'x'") == "5x"
        @test f("'hello world' | capitalize") == "Hello world"
        @test f("'HELLO' | downcase") == "hello"
        @test f("'hello' | upcase") == "HELLO"
        @test f("'  hi  ' | strip") == "hi"
        @test f("'  hi  ' | lstrip") == "hi  "
        @test f("'  hi  ' | rstrip") == "  hi"
        @test render("{{ x | strip_newlines }}"; x = "a\nb") == "ab"
        @test render("{{ x | newline_to_br }}"; x = "a\nb") == "a<br />\nb"
        @test f("'a-b-c' | remove: '-'") == "abc"
        @test f("'a-b-c' | remove_first: '-'") == "ab-c"
        @test f("'a-b' | replace: '-', '+'") == "a+b"
        @test f("'hello' | replace: 'll'") == "heo"
        @test f("'a-b-a' | replace_first: 'a', 'z'") == "z-b-a"
        # Replacing the empty string inserts between every character.
        @test f("'ab' | replace: nil, '#'") == "#a#b#"
    end

    @testset "strip_html" begin
        @test render("{{ x | strip_html }}"; x = "<div>test</div>") == "test"
        @test render("{{ x | strip_html }}"; x = "<div id='a'>test</div>") == "test"
        # script and style lose their contents, not just their tags.
        @test render("{{ x | strip_html }}"; x = "<script>var a = 1;</script>") == ""
        @test render("{{ x | strip_html }}"; x = "<style>p{color:red}</style>") == ""
        @test render("{{ x | strip_html }}"; x = "<!-- gone -->kept") == "kept"
        # Entities are not decoded.
        @test render("{{ x | strip_html }}"; x = "<em>a</em> &amp; b") == "a &amp; b"
    end

    @testset "truncate" begin
        # The length includes the ellipsis.
        @test f("'Ground control to Major Tom.' | truncate: 20") == "Ground control to..."
        @test length(f("'Ground control to Major Tom.' | truncate: 20")) == 20
        @test f("'Ground control to Major Tom.' | truncate: 20, ''") == "Ground control to Ma"
        @test f("'Ground control' | truncate: 20") == "Ground control"
        @test f("'one two three four' | truncatewords: 2") == "one two..."
        @test f("'one two three four' | truncatewords: 2, '-'") == "one two-"
        # A count below one still keeps a word.
        @test f("'one two three' | truncatewords: 0") == "one..."
        # Words split on any whitespace and rejoin with single spaces.
        @test render("{{ x | truncatewords: 3 }}"; x = "one  two\tthree\nfour") == "one two three..."
        @test_throws LiquidArgumentError render("{{ 'a b' | truncatewords: 'foo' }}")
    end

    @testset "arrays" begin
        data = Dict("a" => ["x", "y", "z"])
        @test render("{{ a | join: '#' }}", data) == "x#y#z"
        @test render("{{ a | first }}{{ a | last }}", data) == "xz"
        @test render("{{ a | size }}", data) == "3"
        @test render("{{ a | reverse | join: '#' }}", data) == "z#y#x"
        @test f("(1..5) | join: '#'") == "1#2#3#4#5"
        @test f("'hello' | size") == "5"
        @test f("'hello' | first") == "h"
        # join flattens nested arrays.
        @test render("{{ a | join: '#' }}", Dict("a" => [["x", "y"], "z"])) == "x#y#z"
        @test render("{{ a | uniq | join: '#' }}", Dict("a" => ["a", "b", "a"])) == "a#b"
        @test render("{{ a | compact | join: '#' }}", Dict("a" => ["a", nothing, "b"])) == "a#b"
        @test render("{{ a | concat: b | join: '#' }}",
                     Dict("a" => ["x"], "b" => ["y", "z"])) == "x#y#z"
        @test render("{{ a | map: 'k' | join: '#' }}",
                     Dict("a" => [Dict("k" => 1), Dict("k" => 2)])) == "1#2"
        @test render("{{ a | where: 'k', 2 | size }}",
                     Dict("a" => [Dict("k" => 1), Dict("k" => 2)])) == "1"
    end

    @testset "split" begin
        @test f("'a,b,c' | split: ',' | join: '#'") == "a#b#c"
        @test f("'abc' | split: '' | join: '#'") == "a#b#c"
        # Trailing empty fields are dropped, as in Ruby.
        @test f("',' | split: ',' | size") == "0"
        @test f("'abc' | split: ',' | join: '#'") == "abc"
        # A single space splits on any run of whitespace.
        @test render("{{ x | split: ' ' | join: '#' }}"; x = "a b\nc") == "a#b#c"
    end

    @testset "slice" begin
        @test f("'hello' | slice: 1") == "e"
        @test f("'hello' | slice: 0") == "h"
        @test f("'hello' | slice: 1, 3") == "ell"
        @test f("'Liquid' | slice: -2") == "i"
        @test f("'Liquid' | slice: -2, 2") == "id"
        @test f("'Liquid' | slice: -2, 99") == "id"
        @test f("'hello' | slice: 99") == ""
        @test render("{{ a | slice: 2, 3 | join: '#' }}", Dict("a" => [1, 2, 3, 4, 5])) == "3#4#5"
        @test_throws LiquidArgumentError render("{{ 'hello' | slice: 'foo' }}")
    end

    @testset "sorting" begin
        @test render("{{ a | sort | join: '#' }}", Dict("a" => ["c", "a", "b"])) == "a#b#c"
        @test render("{{ a | sort | join: '#' }}", Dict("a" => [3, 1, 2])) == "1#2#3"
        # sort is case-sensitive, sort_natural is not.
        @test render("{{ a | sort | join: '#' }}", Dict("a" => ["b", "A"])) == "A#b"
        @test render("{{ a | sort_natural | join: '#' }}", Dict("a" => ["b", "A"])) == "A#b"
        @test render("{{ a | sort_natural | join: '#' }}", Dict("a" => ["B", "a"])) == "a#B"
        # sort_natural compares printed forms, so numbers sort as text.
        @test render("{{ a | sort_natural | join: '#' }}", Dict("a" => [9, 1111, 87])) == "1111#87#9"
    end

    @testset "default" begin
        @test f("nil | default: 'x'") == "x"
        @test f("'' | default: 'x'") == "x"
        @test f("false | default: 'x'") == "x"
        @test f("nosuchthing | default: 'x'") == "x"
        @test render("{{ a | default: 'x' }}", Dict("a" => [])) == "x"
        # Zero is not blank.
        @test f("0 | default: 'x'") == "0"
        @test f("'hello' | default: 'x'") == "hello"
        # allow_false lets an explicit false through.
        @test f("false | default: 'x', allow_false: true") == "false"
        @test f("false | default: 'x', allow_false: false") == "x"
    end

    @testset "escaping and urls" begin
        @test f("'<p>a</p>' | escape") == "&lt;p&gt;a&lt;/p&gt;"
        @test f("5 | escape") == "5"
        # escape_once leaves existing entities alone.
        @test f("'&lt;p&gt;' | escape_once") == "&lt;p&gt;"
        @test f("'&lt;p&gt;<b>' | escape_once") == "&lt;p&gt;&lt;b&gt;"
        @test f("'email is bob@example.com!' | url_encode") ==
              "email+is+bob%40example.com%21"
        @test f("'email+is+bob%40example.com%21' | url_decode") ==
              "email is bob@example.com!"
    end

    @testset "date" begin
        @test f("'March 14, 2016' | date: '%b %d, %y'") == "Mar 14, 16"
        @test f("'March 14, 2016' | date: '%Y-%m-%d'") == "2016-03-14"
        @test f("'March 14, 2016' | date: '%A'") == "Monday"
        @test f("'March 14, 2016' | date: '%B'") == "March"
        @test f("'March 14, 2016' | date: '%s'") == "1457913600"
        # A Unix timestamp, as a number or as a string of digits.
        @test f("1152098955 | date: '%m/%d/%Y'") == "07/05/2006"
        @test f("'1152098955' | date: '%m/%d/%Y'") == "07/05/2006"
        # %% is a literal percent.
        @test f("'March 14, 2016' | date: '%%%b'") == "%Mar"
        # The `-` modifier drops zero padding.
        @test f("'March 04, 2016' | date: '%-d/%-m'") == "4/3"
        @test f("'2016-03-14 15:30:45' | date: '%H:%M:%S'") == "15:30:45"
        @test f("'2016-03-14 15:30:45' | date: '%I:%M %p'") == "03:30 PM"
        # An input that is not a date, or a format that is not a string, is a
        # no-op rather than an error.
        @test f("'not a date' | date: '%Y'") == "not a date"
        @test f("'March 14, 2016' | date: nosuchthing") == "March 14, 2016"
        @test f("nosuchthing | date: '%Y'") == ""
    end

    @testset "unknown filters are lenient by default" begin
        @test f("'x' | nosuchfilter") == "x"
        # Wrong arity is an error, though.
        @test_throws LiquidArgumentError render("{{ 'hello' | upcase: 5 }}")
        @test_throws LiquidArgumentError render("{{ 'hello' | append }}")
    end
end
