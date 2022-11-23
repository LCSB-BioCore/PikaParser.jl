
@testset "Precedence cascades" begin
    rules = Dict(
        P.precedence_cascade(
            n -> Symbol(:exprlevel, n),
            (same, next) ->
                :expr => P.first(
                    :plus => P.seq(same, P.token('+'), next),
                    :minus => P.seq(same, P.token('-'), next),
                ),
            (same, next) -> :times => P.seq(same, P.token('*'), next),
            (same, next) -> :power => P.seq(next, P.token('^'), same),
            (_, restart) -> P.first(
                :parens => P.seq(P.token('('), restart, P.token(')')),
                :digits => P.some(P.satisfy(isdigit)),
            ),
        )...,
    )

    g = P.make_grammar([:expr], P.flatten(rules, Char))

    @test issetequal(
        g.names,
        [
            Symbol("digits-1"),
            :digits,
            Symbol("parens-3"),
            Symbol("parens-1"),
            :parens,
            Symbol("exprlevel4-1"),
            :exprlevel4,
            Symbol("power-2"),
            :power,
            :exprlevel3,
            Symbol("times-2"),
            :times,
            :exprlevel2,
            Symbol("minus-2"),
            :exprlevel1,
            :minus,
            Symbol("plus-2"),
            :plus,
            :expr,
        ],
    )

    input = "1*1-1+1^(1+1)^1"
    p = P.parse(g, input)
    m = P.find_match_at!(p, :expr, 1)
    @test p.matches[m].len == length(input)

    fmt(x) = isnothing(x) ? () : x
    @test P.traverse_match(
        p,
        m,
        fold = (rule, match, vals) ->
            length(vals) == 1 ? fmt(vals[1]) : tuple(fmt.(vals)...),
    ) == ((((), (), ()), (), ()), (), ((), (), (((), ((), (), ()), ()), (), ())))
end

@testset "Precedence macro" begin
    rules = Dict(
        :parens => P.seq(P.token('('), :expr, P.token(')')),
        P.@precedences (n -> Symbol(:rule, n)) same next begin
            :expr => P.seq(same, P.token('+'), next)
            P.seq(same, P.token('*'), next)
            P.first(:eekses => P.tokens("xxx"), :parens)
        end
    )

    g = P.make_grammar([:expr], P.flatten(rules, Char))

    @test issetequal(
        g.names,
        [
            Symbol("parens-3"),
            Symbol("parens-1"),
            :parens,
            :eekses,
            Symbol("rule3-1"),
            :rule3,
            Symbol("rule2-1-2"),
            Symbol("rule2-1"),
            :rule2,
            Symbol("expr-2"),
            :rule1,
            :expr,
        ],
    )

    input = "xxx+xxx*(xxx+xxx)*xxx"
    p = P.parse(g, input)
    m = P.find_match_at!(p, :expr, 1)
    @test p.matches[m].len == length(input)
    fmt(x) = isnothing(x) ? () : x

    @test P.traverse_match(
        p,
        m,
        fold = (rule, match, vals) ->
            length(vals) == 1 ? fmt(vals[1]) : tuple(fmt.(vals)...),
    ) == ((), (), (((), (), ((), ((), (), ()), ())), (), ()))
end
