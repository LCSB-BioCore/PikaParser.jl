using Documenter, PikaParser

makedocs(
    modules = [PikaParser],
    clean = false,
    format = Documenter.HTML(),
    sitename = "PikaParser.jl",
    linkcheck = false,
    pages = ["README" => "index.md", "Reference" => "reference.md"],
    strict = [:missing_docs, :cross_references],
)

deploydocs(
    repo = "github.com/exaexa/PikaParser.jl.git",
    target = "build",
    branch = "gh-pages",
    push_preview = false,
)
