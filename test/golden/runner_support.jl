# Loading and checking Golden Liquid cases.  Shared by runner.jl (which turns
# them into tests) and update.jl (which regenerates known_failures.txt).

using JSON

const GOLDEN_DIR = @__DIR__

# Tags whose features are deliberately out of scope for v0.1.  Cases carrying
# any of these, and cases with partial templates, are skipped rather than
# counted as failures.
const OUT_OF_SCOPE = Set([
    "include tag", "render tag", "tablerow tag", "liquid tag", "doc tag",
    "ifchanged tag", "# tag",
    "has filter", "find filter", "find_index filter", "reject filter",
    "sum filter", "squish filter", "replace_last filter", "remove_last filter",
    "base64_encode filter", "base64_decode filter",
    "base64_url_safe_encode filter", "base64_url_safe_decode filter",
])

in_scope(case) =
    isempty(intersect(Set(get(case, "tags", String[])), OUT_OF_SCOPE)) &&
    !haskey(case, "templates")

"""
    golden_cases() -> (cases, total_in_suite)

The suite cases v0.1 is expected to handle, and the size of the whole suite.
"""
function golden_cases()
    all_cases = JSON.parsefile(joinpath(GOLDEN_DIR, "golden_liquid.json"))["tests"]
    return filter(in_scope, all_cases), length(all_cases)
end

"""
    case_passes(case) -> Bool

Whether the engine handles `case` correctly: the rendered output matches
`result`, or the case is marked `invalid` and rendering raised a `LiquidError`.

A Julia error that is not a `LiquidError` never counts as a pass, even for an
`invalid` case: escaping into an uncontrolled error is itself a bug.
"""
function case_passes(case)
    expects_error = get(case, "invalid", false)
    try
        out = Liquid.render(case["template"], get(case, "data", Dict{String,Any}()))
        return expects_error ? false : out == case["result"]
    catch err
        return expects_error && err isa Liquid.LiquidError
    end
end

known_failures() =
    Set(filter(!isempty, strip.(readlines(joinpath(GOLDEN_DIR, "known_failures.txt")))))
