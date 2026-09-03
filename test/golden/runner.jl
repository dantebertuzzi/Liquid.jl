# Run the Golden Liquid suite (https://github.com/jg-rp/golden-liquid), the
# corpus python-liquid validates against.  SOURCE.txt records the pinned commit.
#
# Cases outside the v0.1 scope are skipped and reported separately, so the
# headline number is not inflated.  In-scope cases that do not pass yet are
# listed in known_failures.txt and asserted with `broken=true`: visible in the
# output rather than omitted.  When one starts passing, the run says so, and
# `julia --project=test test/golden/update.jl` refreshes the list.

include(joinpath(@__DIR__, "runner_support.jl"))

function run_golden()
    cases, total_in_suite = golden_cases()
    known = known_failures()
    passed = 0
    unexpected = String[]

    @testset "golden liquid" begin
        for case in cases
            ok = case_passes(case)
            ok && (passed += 1)
            if case["name"] in known
                ok && push!(unexpected, case["name"])
                @test ok broken = true
            else
                @test ok
            end
        end
    end

    percent = round(100 * passed / length(cases); digits = 1)
    println()
    println("golden liquid: $passed/$(length(cases)) in-scope cases pass ($percent%)")
    println("               $(total_in_suite - length(cases)) of $total_in_suite " *
            "suite cases are out of v0.1 scope")
    if !isempty(unexpected)
        println("               $(length(unexpected)) listed failures now pass; " *
                "run `julia --project=test test/golden/update.jl`")
    end
    return passed, length(cases)
end

run_golden()
