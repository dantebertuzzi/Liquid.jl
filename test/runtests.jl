using Liquid
using Test
using Aqua

@testset "Liquid.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Liquid)
    end
    # Write your tests here.
end
