
@testset "Run example from README" begin

    rules = Dict(
        :digits => P.some(:digit => P.satisfy(isdigit)),
        :parens => P.seq(
            P.token('('),
            :expr => P.first(:plusexpr, :minusexpr, :digits, :parens),
            P.token(')'),
        ),
        :plusexpr => P.seq(:expr, P.token('+'), :expr),
        :minusexpr => P.seq(:expr, P.token('-'), :expr),
    )

    rules_flat = P.flatten(rules, Char)

    @test issetequal(
        keys(rules_flat),
        [
            :digit,
            :digits,
            :parens,
            :expr,
            :minusexpr,
            :plusexpr,
            Symbol("parens-1"),
            Symbol("parens-3"),
            Symbol("plusexpr-2"),
            Symbol("minusexpr-2"),
        ],
    )

    g = P.make_grammar(
        [:expr], # top-level rule
        rules_flat,
    )

    @test last(g.names) == :expr

    input = "12-(34+567-8)"
    p = P.parse(g, input)

    mid = P.find_match_at!(p, :expr, 1)
    @test mid != 0
    @test p.matches[mid].pos == 1
    @test P.view_match(p, mid) == input

    m = p.matches[P.find_match_at!(p, :expr, 1)]
    @test m.len == length(input)

    x = P.traverse_match(p, P.find_match_at!(p, :expr, 1))
    @test x == :(expr(
        minusexpr(
            expr(digits(digit("1"), digit("2"))),
            var"minusexpr-2"("-"),
            expr(
                parens(
                    var"parens-1"("("),
                    expr(
                        plusexpr(
                            expr(digits(digit("3"), digit("4"))),
                            var"plusexpr-2"("+"),
                            expr(
                                minusexpr(
                                    expr(digits(digit("5"), digit("6"), digit("7"))),
                                    var"minusexpr-2"("-"),
                                    expr(digits(digit("8"))),
                                ),
                            ),
                        ),
                    ),
                    var"parens-3"(")"),
                ),
            ),
        ),
    ))

    res = P.traverse_match(
        p,
        P.find_match_at!(p, :expr, 1),
        fold = (m, p, subvals) ->
            m.rule == :digits ? parse(Int, m.view) :
            m.rule == :expr ? subvals[1] :
            m.rule == :parens ? subvals[2] :
            m.rule == :plusexpr ? subvals[1] + subvals[3] :
            m.rule == :minusexpr ? subvals[1] - subvals[3] : nothing,
    )

    @test res == eval(Meta.parse(input))
end
