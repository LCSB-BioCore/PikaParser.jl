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
include("parse.jl")
include("traverse.jl")

end # module
