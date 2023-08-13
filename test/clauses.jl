
@testset "FollowedBy-style clauses" begin
    rules = Dict(
        "seq" => P.many(P.first(P.fail, "a", "b")),
        "a" => P.seq(P.token(1), P.epsilon, P.not_followed_by(P.token(1))),
        "b" => P.seq(P.token(2), P.followed_by(P.token(1))),
    )

    g = P.make_grammar(["seq"], P.flatten(rules, Int, (s, idx) -> "$(s)_$idx"))

    toks = [1, 2, 1, 2, 1]
    p = P.parse(g, toks)

    m = P.find_match_at!(p, "seq", 1)
    @test m != 0
    @test p.matches[m].last == lastindex(toks)

    @test P.traverse_match(
        p,
        m,
        fold = (m, p, subvals) -> Expr(:call, Symbol(m.rule), subvals...),
    ) == :(seq(
        seq_1(a(a_1(), a_2(), a_3())),
        seq_1(b(b_1(), b_2(b_2_1()))),
        seq_1(a(a_1(), a_2(), a_3())),
        seq_1(b(b_1(), b_2(b_2_1()))),
        seq_1(a(a_1(), a_2(), a_3())),
    ))

    toks = [1, 1, 2]
    p = P.parse(g, toks)
    @test p.matches[P.find_match_at!(p, "seq", 1)].last == 0
    @test P.find_match_at!(p, "seq", 2) != 0
    @test p.matches[P.find_match_at!(p, "seq", 2)].last == 2
    @test p.matches[P.find_match_at!(p, "seq", 3)].last == 2

    toks = [2, 2, 2, 1]
    p = P.parse(g, toks)
    @test p.matches[P.find_match_at!(p, "seq", 1)].last == 0
    @test p.matches[P.find_match_at!(p, "seq", 2)].last == 1
    @test p.matches[P.find_match_at!(p, "seq", 3)].last == 4
end

@testset "Multiple token matches" begin
    rules = Dict(
        3 => P.first(
            11 => P.scan(toks -> length(toks) >= 2 && toks[1] == toks[2] ? 2 : 0),
            P.tokens([:one, :two, :three]),
        ),
    )

    g = P.make_grammar([3], P.flatten(rules, Symbol, (s, idx) -> 1000 * s + idx))

    @test issetequal(g.names, [3, 11, 3002])

    p = P.parse(g, [:one, :one, :two, :three, :three])
    @test all(
        ((P.find_match_at!(p, 3, pos) for pos = 1:5) .> 0) .==
        [true, true, false, true, false],
    )
end

@testset "Tie" begin
    rules = Dict(
        :item => P.satisfy(x -> isdigit(x) || isletter(x)),
        :sep => P.token(','),
        :list => P.tie(P.seq(P.seq(:item), P.many(:sepitem => P.seq(:sep, :item)))),
    )

    g = P.make_grammar([:list], P.flatten(rules, Char))

    input = "1,ए,A,β,Ж"
    p = P.parse(g, input)

    mid = P.find_match_at!(p, :list, 1)
    @test mid != 0
    @test p.matches[mid].last == lastindex(input)
    @test P.traverse_match(p, mid) == :(list(
        item("1"),
        sepitem(sep(","), item("ए")),
        sepitem(sep(","), item("A")),
        sepitem(sep(","), item("β")),
        sepitem(sep(","), item("Ж")),
    ))
end

@testset "Flatten complains about duplicates" begin
    rules = Dict(:x => P.seq(:x => P.fail))

    @test_throws DomainError P.flatten(rules, Char)
end

@testset "Corner-case epsilon matches" begin
    str = "whateveρ"

    rules = Dict(:x => P.followed_by(P.epsilon))

    p = P.parse(P.make_grammar([:x], P.flatten(rules, Char)), str)

    @test P.find_match_at!(p, :x, 1) != 0
    @test P.find_match_at!(p, :x, 8) != 0
    # no unnecessary allocation
    @test P.find_match_at!(p, :x, 1) == P.find_match_at!(p, :x, 1)

    # tie epsilon match
    rules = Dict(:x => P.tie(P.epsilon))
    p = P.parse(P.make_grammar([:x], P.flatten(rules, Char)), str)

    @test P.traverse_match(p, P.find_match_at!(p, :x, 1)) == :(x())

    rules = Dict(:x => P.end_of_input)
    p = P.parse(P.make_grammar([:x], P.flatten(rules, Char)), str)

    @test P.find_match_at!(p, :x, firstindex(str)) == 0
    @test P.find_match_at!(p, :x, lastindex(str)) == 0
    @test P.find_match_at!(p, :x, nextind(str, lastindex(str))) != 0
end

@testset "Invalid epsilon matches are avoided" begin
    rules = Dict(:x => P.not_followed_by(P.epsilon))
    @test_throws ErrorException P.make_grammar([:x], P.flatten(rules, Char))

    # thanks go to @CptWesley for bringing this up in
    # https://github.com/lukehutch/pikaparser/issues/35
    rules = Dict(:x => P.first(P.token('a'), P.epsilon), :y => P.first(P.seq(:y, :x), :x))
    @test_throws ErrorException P.make_grammar([:y], P.flatten(rules, Char))
end
