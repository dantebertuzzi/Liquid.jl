# Rendering a template must never reach Julia: no eval, no reflection, no
# method call named by template text.  A hostile template's worst case is
# useless output or a controlled error.

using Liquid: render, parse_template, Environment, FileSystemLoader,
              get_template, liquid_get, liquid_properties, @liquid_drop,
              LiquidSyntaxError, LiquidError

# A type that has not opted in at all: everything about it must stay invisible.
struct Opaque
    password::String
    token::String
end

# A type that opts in to one field of two.
struct Account
    name::String
    secret::String
end
Liquid.liquid_properties(::Type{Account}) = (:name,)

# The macro form, and a computed property on top of it.
struct Product
    title::String
    cost::Float64
end
@liquid_drop Product title
function Liquid.liquid_get(p::Product, key::AbstractString)
    key == "shouting" && return uppercase(p.title)
    return invoke(Liquid.liquid_get, Tuple{Any,AbstractString}, p, key)
end

@testset "security" begin
    @testset "a struct is opaque unless it opts in" begin
        o = Opaque("hunter2", "sk-secret")
        @test liquid_properties(Opaque) == ()
        @test render("[{{ o.password }}]"; o = o) == "[]"
        @test render("[{{ o.token }}]"; o = o) == "[]"
        @test render("[{{ o }}]"; o = o) == "[]"
        @test render("[{{ o['password'] }}]"; o = o) == "[]"
        # Not even through a computed subscript.
        @test render("[{{ o[k] }}]", Dict("o" => o, "k" => "password")) == "[]"
    end

    @testset "opting in exposes exactly the declared fields" begin
        a = Account("ada", "sk-secret")
        @test render("{{ a.name }}"; a = a) == "ada"
        @test render("[{{ a.secret }}]"; a = a) == "[]"
        @test render("[{{ a[k] }}]", Dict("a" => a, "k" => "secret")) == "[]"

        p = Product("widget", 9.99)
        @test render("{{ p.title }}"; p = p) == "widget"
        @test render("[{{ p.cost }}]"; p = p) == "[]"
        # A computed property, via the liquid_get override.
        @test render("{{ p.shouting }}"; p = p) == "WIDGET"
    end

    @testset "template text cannot name Julia" begin
        # None of these reach anything; they all render empty.
        hostile = [
            "{{ Base }}", "{{ Main }}", "{{ Core }}",
            "{{ Base.run }}", "{{ Main.Base }}",
            "{{ x.__class__ }}", "{{ x.__dict__ }}",
            "{{ x.fieldnames }}", "{{ x.parent }}",
            "{{ [\"Base\"] }}", "{{ x['Base']['run'] }}",
            "{{ eval }}", "{{ include }}", "{{ read }}",
        ]
        for src in hostile
            @test render(src; x = Account("a", "b")) == ""
        end
    end

    @testset "hostile templates fail controlled or not at all" begin
        # Malformed input is a LiquidError with a position, never a Julia error.
        for src in ["{{ ", "{% ", "{% if %}", "{% nope %}", "{{ a b c }}",
                    "{% for %}", "{% endfor %}", "{{ | }}", "{% raw %}"]
            @test_throws LiquidError parse_template(src)
        end

        # Deep nesting parses and renders without blowing the stack.
        deep = repeat("{% if true %}", 60) * "x" * repeat("{% endif %}", 60)
        @test render(deep) == "x"

        # A huge range does not allocate: it is sliced lazily.
        @test render("{% for i in (1..1000000000) limit: 3 %}{{ i }}{% endfor %}") == "123"
        @test (@allocated render("{% for i in (1..1000000000) limit: 2 %}x{% endfor %}")) < 1_000_000
    end

    @testset "FileSystemLoader stays inside its root" begin
        mktempdir() do dir
            mkpath(joinpath(dir, "templates"))
            root = joinpath(dir, "templates")
            write(joinpath(root, "ok.liquid"), "hello {{ name }}")
            write(joinpath(dir, "secret.liquid"), "SECRET")

            env = Environment(loader = FileSystemLoader(root))
            @test render(get_template(env, "ok.liquid"); name = "world") == "hello world"

            # Every spelling of "go up one directory" is refused.
            for name in ["../secret.liquid", "./../secret.liquid",
                         "a/../../secret.liquid", "../templates/../secret.liquid"]
                @test_throws ArgumentError get_template(env, name)
            end
            @test_throws ArgumentError get_template(env, "nope.liquid")
        end
    end

    @testset "the package contains no evaluation machinery" begin
        # An architectural invariant, checked against the source itself: if
        # someone ever adds an eval to the render path, this fails.
        srcdir = joinpath(dirname(dirname(pathof(Liquid))), "src")
        files = String[]
        for (root, _, names) in walkdir(srcdir), name in names
            endswith(name, ".jl") && push!(files, joinpath(root, name))
        end
        @test !isempty(files)

        for file in files
            text = read(file, String)
            for forbidden in ["@eval", "Meta.parse", "Core.eval", "invokelatest",
                              "getproperty(", "@generated"]
                @test !occursin(forbidden, text)
            end
            # `eval(` only ever appears as part of `evaluate(`.
            @test !occursin(r"(?<![a-z_])eval\(", text)
            # getfield is allowed in exactly one place: the drop interface,
            # and only with a symbol the type's author listed.
            if occursin("getfield(", text)
                @test basename(file) == "drops.jl"
            end
        end
    end
end
