"""
$(README)
"""
module PikaParser

using DataStructures
using DocStringExtensions

include("structs.jl")
include("clauses.jl")
include("frontend.jl")
include("grammar.jl")
include("memo.jl")
include("parse.jl")
include("q.jl")
include("traverse.jl")

end # module
