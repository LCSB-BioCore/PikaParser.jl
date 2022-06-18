
using PikaParser
using Test

const P = PikaParser

# This just tests the trivial example from the README.

@testset "Run example from README" begin

    rules = Dict{Symbol,P.Clause{Symbol}}(
        # Terminal matches if the boolean function matches on input token.
        :plus => P.Terminal{Symbol}(==('+')),
        :minus => P.Terminal{Symbol}(==('-')),
        :digit => P.Terminal{Symbol}(isdigit),
        :digits => P.OneOrMore(:digit), # greedy repetition
        :plusexpr => P.Seq([:expr, :plus, :expr]), # sequence of matches
        :minusexpr => P.Seq([:expr, :minus, :expr]),
        :popen => P.Terminal{Symbol}(==('(')),
        :pclose => P.Terminal{Symbol}(==(')')),
        :parens => P.Seq([:popen, :expr, :pclose]),

        # return whichever first match
        :expr => P.First([:plusexpr, :minusexpr, :digits, :parens]),
    )

    g = P.make_grammar(
        [:expr], # top-level rule
        rules,
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
            minus(),
            expr(
                parens(
                    popen(),
                    expr(
                        plusexpr(
                            expr(digits(digit(), digit())),
                            plus(),
                            expr(
                                minusexpr(
                                    expr(digits(digit(), digit(), digit())),
                                    minus(),
                                    expr(digits(digit())),
                                ),
                            ),
                        ),
                    ),
                    pclose(),
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
