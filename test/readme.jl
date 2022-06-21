
@testset "Run example from README" begin

    rules = Dict(
        :digits => P.one_or_more(:digit => P.satisfy(isdigit)),
        :parens => P.seq(
            P.token('('),
            :expr => P.first(:plusexpr, :minusexpr, :digits, :parens),
            P.token(')'),
        ),
        :plusexpr => P.seq(:expr, P.token('+'), :expr),
        :minusexpr => P.seq(:expr, P.token('-'), :expr),
    )

    rules_flat = P.flatten(rules)

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

    input_str = "12-(34+567-8)"
    input = collect(input_str)
    p = P.parse(g, input)

    pos, rule = P.find_first_parse_at(g, p, 1)
    @test pos == 1
    @test rule == :expr

    mid = P.find_match_at(g, p, :expr, 1)

    @test !isnothing(mid)

    m = p.matches[P.find_match_at(g, p, :expr, 1)]
    @test m.pos == 1
    @test m.len == length(input)

    x = P.traverse_match(g, p, P.find_match_at(g, p, :expr, 1), :expr)
    @test x == :(expr(
        minusexpr(
            expr(digits(digit(), digit())),
            var"minusexpr-2"(),
            expr(
                parens(
                    var"parens-1"(),
                    expr(
                        plusexpr(
                            expr(digits(digit(), digit())),
                            var"plusexpr-2"(),
                            expr(
                                minusexpr(
                                    expr(digits(digit(), digit(), digit())),
                                    var"minusexpr-2"(),
                                    expr(digits(digit())),
                                ),
                            ),
                        ),
                    ),
                    var"parens-3"(),
                ),
            ),
        ),
    ))

    res = P.traverse_match(
        g,
        p,
        P.find_match_at(g, p, :expr, 1),
        :expr,
        fold = (rule, umatch, subvals) ->
            rule == :digits ?
            parse(Int, String(input[umatch.pos:umatch.pos+umatch.len-1])) :
            rule == :expr ? subvals[1] :
            rule == :parens ? subvals[2] :
            rule == :plusexpr ? subvals[1] + subvals[3] :
            rule == :minusexpr ? subvals[1] - subvals[3] : nothing,
    )

    @test res == eval(Meta.parse(input_str))
end
