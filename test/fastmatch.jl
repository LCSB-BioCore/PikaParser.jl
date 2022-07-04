
@testset "Fast matching" begin
    rules = Dict(
        :digits => P.some(:digit => P.fail),
        :seq => P.seq(:digits, P.many(:cont => P.seq(:sep => P.fail, :digits))),
    )

    g = P.make_grammar([:seq], P.flatten(rules))
    input = collect("123,234,345")
    p = P.parse(g, input, (input, i, r) -> input[i] == ',' ? r(:sep, 1) : r(:digit, 1))

    mid = P.find_match_at!(p, :seq, 1)
    @test p.matches[mid].len == length(input)

    x = P.traverse_match(
        p,
        mid,
        fold = (rule, match, subvals) ->
            rule == :digits ?
            parse(Int, String(P.view_match(p, match))) :
            rule == :seq ? [subvals[1], subvals[2]...] :
            rule == :cont ? subvals[2] : subvals,
    )
    @test x == [123, 234, 345]
end
