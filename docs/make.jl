using Documenter, Literate, PikaParser

examples = filter(x -> endswith(x, ".jl"), readdir(joinpath(@__DIR__, "src"), join = true))

for example in examples
    Literate.markdown(
        example,
        joinpath(@__DIR__, "src"),
        repo_root_url = "https://github.com/LCSB-BioCore/PikaParser.jl/blob/master",
    )
end

example_mds = first.(splitext.(basename.(examples))) .* ".md"

makedocs(
    modules = [PikaParser],
    clean = false,
    format = Documenter.HTML(
        ansicolor = true,
        canonical = "https://lcsb-biocore.github.io/PikaParser.jl/stable/",
    ),
    sitename = "PikaParser.jl",
    linkcheck = false,
    pages = ["README" => "index.md"; example_mds; "Reference" => "reference.md"],
    strict = [:missing_docs, :cross_references, :example_block],
)

deploydocs(
    repo = "github.com/LCSB-BioCore/PikaParser.jl.git",
    target = "build",
    branch = "gh-pages",
    push_preview = false,
)
