
@testset "FollowedBy-style clauses" begin
    rules = Dict(
        "seq" => P.zero_or_more(P.first("a", "b")),
        "a" => P.seq(P.token(1), P.not_followed_by(P.token(1))),
        "b" => P.seq(P.token(2), P.followed_by(P.token(1))),
    )

    g = P.make_grammar(["seq"], P.flatten(rules, (s, idx) -> "$(s)_$idx"))

    toks = [1, 2, 1, 2, 1]
    p = P.parse(g, toks)

    m = P.find_match_at(g, p, "seq", 1)
    @test !isnothing(m)
    @test p.matches[m].len == length(toks)

    @test P.traverse_match(
        g,
        p,
        m,
        "seq",
        fold = (rule, match, subvals) -> Expr(:call, Symbol(rule), subvals...),
    ) == :(seq(
        seq_1(a(a_1(), a_2())),
        seq_1(b(b_1(), b_2(b_2_1()))),
        seq_1(a(a_1(), a_2())),
        seq_1(b(b_1(), b_2(b_2_1()))),
        seq_1(a(a_1(), a_2())),
    ))

    toks = [1, 1, 2]
    p = P.parse(g, toks)
    @test isnothing(P.find_match_at(g, p, "seq", 1))
    @test !isnothing(P.find_match_at(g, p, "seq", 2))
    @test p.matches[P.find_match_at(g, p, "seq", 2)].len == 1

    toks = [2, 2, 2, 1]
    p = P.parse(g, toks)
    @test isnothing(P.find_match_at(g, p, "seq", 1))
    @test isnothing(P.find_match_at(g, p, "seq", 2))
    @test !isnothing(P.find_match_at(g, p, "seq", 3))
    @test p.matches[P.find_match_at(g, p, "seq", 3)].len == 2
end

@testset "Multiple token matches" begin
    rules = Dict(
        3 => P.first(
            11 => P.take_n(toks -> length(toks) >= 2 && toks[1] == toks[2] ? 2 : nothing),
            P.tokens([:one, :two, :three]),
        ),
    )

    g = P.make_grammar([3], P.flatten(rules, (s, idx) -> 1000 * s + idx))

    @test issetequal(g.names, [3, 11, 3002])

    p = P.parse(g, [:one, :one, :two, :three, :three])
    @test all(
        isnothing.(P.find_match_at(g, p, 3, pos) for pos = 1:5) .==
        [false, false, true, false, true],
    )
end
