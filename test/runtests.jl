using Liquid
using Test

include("helpers.jl")

@testset "Liquid.jl" begin
    include("test_lexer.jl")
    include("test_exprlexer.jl")
    include("test_expressions.jl")
    include("test_parser.jl")
    include("test_coercion.jl")
    include("test_render.jl")
    include("test_tags.jl")
    include("test_filters.jl")
    include("test_security.jl")
    include("golden/runner.jl")
    include("test_aqua.jl")
end
