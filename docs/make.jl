using Liquid
using Documenter

DocMeta.setdocmeta!(Liquid, :DocTestSetup, :(using Liquid); recursive=true)

makedocs(;
    modules=[Liquid],
    authors="Dante Bertuzzi <dantesbertuzzi@gmail.com>",
    sitename="Liquid.jl",
    format=Documenter.HTML(;
        canonical="https://dantebertuzzi.github.io/Liquid.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Passing data" => "data.md",
        "Template reference" => "templates.md",
        "Extending" => "extending.md",
        "API" => "api.md",
    ],
    # Every exported name must be documented; internals are documented as they
    # are needed rather than exhaustively.
    checkdocs=:exports,
)

deploydocs(;
    repo="github.com/dantebertuzzi/Liquid.jl",
    devbranch="main",
)
