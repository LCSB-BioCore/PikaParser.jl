
function lookup_best_match_id!(k::MemoKey, st::ParserState)::MatchResult
    mid = get(st.memo, k, nothing)
    isnothing(mid) || return mid

    if st.grammar.can_match_epsilon[k.clause]
        return match_epsilon!(st.grammar.clauses[k.clause], k.clause, k.start_pos, st)
    end

    return nothing
end

function new_match!(match::Match, st::ParserState)::Int
    push!(st.matches, match)
    return length(st.matches)
end

function add_match!(k::MemoKey, match::MatchResult, st::ParserState)
    updated = false
    if !isnothing(match)
        old = get(st.memo, k, nothing)
        if isnothing(old) || better_match_than(
            st.grammar.clauses[k.clause],
            st.matches[match],
            st.matches[old],
        )
            st.memo[k] = match
            updated = true
        end
    end
    for seed in st.grammar.seed_clauses[k.clause]
        if updated || st.grammar.can_match_epsilon[seed]
            push!(st.q, seed)
        end
    end
end

"""
$(TYPEDSIGNATURES)

Take a [`Grammar`](@ref) and an indexable input sequence, and produce a
[`ParseResult`](@ref) that describes all matched grammar productions.

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

Use [`find_first_parse_at`](@ref) or [`find_match_at`](@ref) to extract matches
from [`ParseResult`](@ref).

Pika parsing never really fails. Instead, in case when the grammar rule is not
matched in the input, the expected rule match match is either not going to be
found at the starting position with [`find_match_at`](@ref), or it will not
span the whole input.

# Example

    parse(
        g,
        collect("abcde123"),
        (input, i, match) -> isdigit(input[i]) ? match(:digit, 1) : match(:letter, 1),
    )
"""
function parse(grammar::Grammar, input::AbstractVector, fast_match = nothing)::ParseResult
    st = ParserState(grammar, MemoTable(), PikaQueue(), Match[], input)
    sizehint!(st.matches, length(input)) # hopefully avoids a painful part of the overhead

    for i in reverse(eachindex(input))
        if isnothing(fast_match)
            push!(st.q, grammar.terminals...)
        else
            fast_match(
                input,
                i,
                (rid, len) -> let cl = grammar.idx[rid]
                    add_match!(MemoKey(cl, i), new_match!(Match(i, len, 0, []), st), st)
                end,
            )
        end
        while !isempty(st.q)
            clause = pop!(st.q)
            match = match_clause!(grammar.clauses[clause], clause, i, st)
            add_match!(MemoKey(clause, i), match, st)
        end
    end

    return ParseResult(st.memo, st.matches)
end
