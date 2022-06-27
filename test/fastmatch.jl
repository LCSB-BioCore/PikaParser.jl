
@testset "Fast matching" begin
    rules = Dict(
        :digits => P.one_or_more(:digit => P.fail),
        :seq => P.seq(:digits, P.zero_or_more(:cont => P.seq(:sep => P.fail, :digits))),
    )

    g = P.make_grammar([:seq], P.flatten(rules))
    input = collect("123,234,345")
    p = P.parse(g, input, (input, i, r) -> input[i] == ',' ? r(:sep, 1) : r(:digit, 1))

    mid = P.find_match_at(g, p, :seq, 1)
    @test p.matches[mid].len == length(input)

    x = P.traverse_match(
        g,
        p,
        mid,
        :seq,
        fold = (rule, match, subvals) ->
            rule == :digits ?
            parse(Int, String(input[match.pos:match.pos+match.len-1])) :
            rule == :seq ? [subvals[1], subvals[2]...] :
            rule == :cont ? subvals[2] : subvals,
    )
    @test x == [123, 234, 345]
end
