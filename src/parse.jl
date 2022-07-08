
function lookup_best_match_id!(pos::Int, clause::Int, st::ParserState)::MatchResult
    pos <= length(st.memo) || return nothing
    mid = get(st.memo[pos], clause, nothing)
    isnothing(mid) || return mid

    if st.grammar.can_match_epsilon[clause]
        return match_epsilon!(st.grammar.clauses[clause], clause, pos, st)
    end

    return nothing
end

function new_match!(match::Match, st::ParserState)::Int
    push!(st.matches, match)
    return length(st.matches)
end

function add_match!(pos::Int, clause::Int, match::MatchResult, st::ParserState)
    updated = false
    if !isnothing(match)
        old = get(st.memo[pos], clause, nothing)
        if isnothing(old) || better_match_than(
            st.grammar.clauses[clause],
            st.matches[match],
            st.matches[old],
        )
            st.memo[pos][clause] = match
            updated = true
        end
    end
    for seed in st.grammar.seed_clauses[clause]
        if updated || st.grammar.can_match_epsilon[seed]
            push!(st.q, seed)
        end
    end
end

"""
$(TYPEDSIGNATURES)

Take a [`Grammar`](@ref) and an indexable input sequence, and return a final
[`ParserState`](@ref) that contains all matched grammar productions.

# Fast terminal matching

If `fast_match` is specified, the function does not match terminals using the
associated grammar rules, but with a `fast_match` function that reports the
matched terminals via a callback. The function is called exactly once for each
position in `input` in reverse order (i.e., the indexes will follow
`reverse(1:length(input))`, which can be utilized by the application for
optimization).  The call parameters consist of the input vector, position in
the input vector, and a "report" function used to send back a clause ID (of
same type as `G` in `typeof(grammar)`) and the length of the terminal matches
that can found at that position. Calls to the reporting function can be
repeated if more terminal types match. Terminals not reported by the calls to
`fast_match` will not be matched.

For complicated grammars, this may be much faster than having the parser to try
matching all terminal types at each position.

# Results

Use [`find_match_at!`](@ref) to extract matches from [`ParserState`](@ref).

Pika parsing never really fails. Instead, in case when the grammar rule is not
matched in the input, the expected rule match match is either not going to be
found at the starting position with [`find_match_at!`](@ref), or it will not
span the whole input.

# Example

    parse(
        g,
        collect("abcde123"),
        (input, i, match) -> isdigit(input[i]) ? match(:digit, 1) : match(:letter, 1),
    )
"""
function parse(
    grammar::Grammar{G},
    input::I,
    fast_match = nothing,
)::ParserState{G,I} where {G,I<:AbstractVector}
    st = ParserState(
        grammar,
        [Dict{Int,Int}() for _ in 1:1+length(input)],
        PikaQueue(length(grammar.clauses)),
        Match[],
        input,
    )

    terminal_q = PikaQueue(length(grammar.clauses))
    reset!(terminal_q, grammar.terminals)

    for i in reverse(eachindex(input))
        if isnothing(fast_match)
            reset!(st.q, terminal_q)
        else
            fast_match(
                input,
                i,
                (rid, len) -> let cl = grammar.idx[rid]
                    add_match!(i, cl, new_match!(Match(cl, i, len, 0, []), st), st)
                end,
            )
        end
        while !isempty(st.q)
            clause = pop!(st.q)
            match = match_clause!(grammar.clauses[clause], clause, i, st)
            add_match!(i, clause, match, st)
        end
    end

    st
end
