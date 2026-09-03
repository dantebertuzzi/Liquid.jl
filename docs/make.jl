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
    ],
)

deploydocs(;
    repo="github.com/dantebertuzzi/Liquid.jl",
    devbranch="main",
)
