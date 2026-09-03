using Liquid: is_truthy, to_liquid_string, to_number, is_blank, is_empty,
              liquid_equal, liquid_less, liquid_contains, compare,
              IncomparableValues, EMPTY, BLANK,
              EQ, NE, GT, LT, GE, LE, CONTAINS

@testset "coercion" begin
    @testset "truthiness: only false and nil are false" begin
        @test is_truthy(true)
        @test !is_truthy(false)
        @test !is_truthy(nothing)
        @test !is_truthy(missing)
        # The ones that catch people out: these are all TRUE in Liquid.
        @test is_truthy(0)
        @test is_truthy(0.0)
        @test is_truthy("")
        @test is_truthy([])
        @test is_truthy(Dict())
        @test is_truthy("false")
    end

    @testset "to_liquid_string" begin
        @test to_liquid_string(nothing) == ""
        @test to_liquid_string(missing) == ""
        @test to_liquid_string(true) == "true"
        @test to_liquid_string(false) == "false"
        @test to_liquid_string("abc") == "abc"
        @test to_liquid_string(42) == "42"
        @test to_liquid_string(-7) == "-7"
        # Integers and floats print differently, as in the reference suite.
        @test to_liquid_string(5.0) == "5.0"
        @test to_liquid_string(5) == "5"
        @test to_liquid_string(1.23) == "1.23"
        # An array joins with no separator at all.
        @test to_liquid_string([1, 2, 3]) == "123"
        @test to_liquid_string(["a", "b"]) == "ab"
        @test to_liquid_string(1:3) == "123"
        @test to_liquid_string(EMPTY) == ""
        @test to_liquid_string(BLANK) == ""
    end

    @testset "to_number" begin
        @test to_number(42) === 42
        @test to_number(1.5) === 1.5
        @test to_number("42") === 42
        @test to_number("1.5") === 1.5
        @test to_number("-3") === -3
        @test to_number(" 7 ") === 7
        # A leading number is read out of a string; a bare word is not a number.
        @test to_number("12abc") === 12
        @test to_number("abc") === nothing
        @test to_number("") === nothing
        @test to_number(nothing) === nothing
        # A Bool is not a number in Liquid.
        @test to_number(true) === nothing
    end

    @testset "blank and empty" begin
        @test is_blank(nothing) && is_blank(missing) && is_blank(false)
        @test is_blank("") && is_blank("   ") && is_blank("\n\t")
        @test is_blank([]) && is_blank(Dict())
        @test !is_blank("x") && !is_blank(true) && !is_blank(0)

        @test is_empty("") && is_empty([]) && is_empty(Dict())
        # Unlike blank: whitespace is not empty, and nil is not empty.
        @test !is_empty("   ")
        @test !is_empty(nothing)
        @test !is_empty(false)
    end

    @testset "equality never raises" begin
        @test liquid_equal(nothing, nothing)
        @test liquid_equal(nothing, missing)
        @test !liquid_equal(nothing, 0)
        @test !liquid_equal(nothing, "")
        @test liquid_equal(1, 1.0)
        @test liquid_equal("a", "a")
        @test !liquid_equal("1", 1)
        # A boolean is not 1 in Liquid.
        @test !liquid_equal(true, 1)
        @test liquid_equal([1, 2], [1, 2])
        @test !liquid_equal([1, 2], [1, 2, 3])
        # Comparing wildly different types is false, not an error.
        @test !liquid_equal("abc", [1])
        @test !liquid_equal(Dict(), 3)

        # empty and blank match anything that is empty or blank.
        @test liquid_equal(EMPTY, "") && liquid_equal("", EMPTY)
        @test liquid_equal(EMPTY, []) && liquid_equal(EMPTY, Dict())
        @test !liquid_equal(EMPTY, "  ")
        @test !liquid_equal(EMPTY, nothing)
        @test liquid_equal(BLANK, "") && liquid_equal(BLANK, "   ")
        @test liquid_equal(BLANK, nothing) && liquid_equal(BLANK, false)
        @test !liquid_equal(BLANK, "x")
    end

    @testset "order comparison is the one strict operation" begin
        @test liquid_less(1, 2)
        @test !liquid_less(2, 1)
        @test liquid_less(1, 2.5)
        # Strings compare lexicographically: 'abc' < 'acb' is true.
        @test liquid_less("abc", "acb")
        @test !liquid_less("bbb", "aaa")

        # Mixing a string and a number raises: `{% if '2' > 1 %}` is an error.
        @test_throws IncomparableValues liquid_less("2", 1)
        @test_throws IncomparableValues liquid_less(1, "2")
        @test_throws IncomparableValues liquid_less(nothing, 1)
        @test_throws IncomparableValues liquid_less(true, false)
    end

    @testset "compare" begin
        @test compare(EQ, 1, 1) && !compare(NE, 1, 1)
        @test compare(LT, 1, 2) && compare(GT, 2, 1)
        @test compare(LE, 1, 1) && compare(GE, 1, 1)
        @test compare(LE, 1, 2) && !compare(GE, 1, 2)

        # An order comparison against empty/blank is false in both directions,
        # never an error, and this is not the negation of the opposite operator.
        for op in (LT, GT, LE, GE)
            @test compare(op, BLANK, 1) == false
            @test compare(op, 1, BLANK) == false
            @test compare(op, EMPTY, 1) == false
            @test compare(op, 1, EMPTY) == false
        end
    end

    @testset "contains" begin
        @test compare(CONTAINS, "hello", "ell")
        @test !compare(CONTAINS, "hello", "xyz")
        @test compare(CONTAINS, ["a", "b"], "a")
        @test !compare(CONTAINS, ["a", "b"], "c")
        @test compare(CONTAINS, [1, 2], 2)
        # nil contains nothing, and that is not an error.
        @test !compare(CONTAINS, nothing, "a")
        @test !compare(CONTAINS, 42, "a")
    end
end
