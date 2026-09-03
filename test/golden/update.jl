# Regenerate known_failures.txt from the current state of the engine.
#
# Run from the package root after implementing something new:
#     julia --project=test test/golden/update.jl
#
# Review the diff before committing: the list should only ever shrink.

using Liquid, JSON
include(joinpath(@__DIR__, "runner_support.jl"))

cases, _ = golden_cases()
failures = sort!(unique!([case["name"] for case in cases if !case_passes(case)]))

open(joinpath(@__DIR__, "known_failures.txt"), "w") do io
    for name in failures
        println(io, name)
    end
end

println("wrote $(length(failures)) known failures of $(length(cases)) in-scope cases " *
        "($(length(cases) - length(failures)) passing)")
