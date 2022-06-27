
import PikaParser as P
using Test

@testset "PikaParser tests" begin
    include("readme.jl")
    include("clauses.jl")
    include("precedence.jl")
    include("fastmatch.jl")
end
