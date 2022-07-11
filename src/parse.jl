
function lookup_best_match_id!(pos::Int, clause::Int, st::ParserState)::MatchResult
    mid = match_find!(st, clause, pos)
    mid!=0 && return mid

    if st.grammar.can_match_epsilon[clause]
        return match_epsilon!(st.grammar.clauses[clause], clause, pos, st)
    end

    return 0
end

function new_match!(match::Match, st::ParserState)::Int
    push!(st.matches, match)
    return length(st.matches)
end

function add_match!(pos::Int, clause::Int, match::Int, st::ParserState)
    updated = false

    if match != 0
        old = match_find!(st, clause, pos)
        if old==0 ||
           better_match_than(st.grammar.clauses[clause], st.matches[match], st.matches[old])
            match_insert!(st, match)
            updated = true
        end
    end

    for seed in st.grammar.seed_clauses[clause]
        if updated || st.grammar.can_match_epsilon[seed]
            push!(st.q, seed)
        end
    end

    nothing
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
    grammar::Grammar{G,T},
    input::I,
    fast_match = nothing,
)::ParserState{G,T,I} where {G,T,I<:AbstractVector{T}}
    st = ParserState{G,T,I}(grammar, PikaQueue(length(grammar.clauses)), Match[], 0, Int[], input)

    # a queue pre-filled with terminal matches (used so that we don't need to refill it manually everytime)
    terminal_q = PikaQueue(length(grammar.clauses))
    reset!(terminal_q, grammar.terminals)
    match = Ref{Int}(0)
    pclause = Ref{Int}(0)
    ii = Ref{Int}(0)

    for i in reverse(eachindex(input))
        if isnothing(fast_match)
            reset!(st.q, terminal_q)
        else
            fast_match(
                input,
                i,
                (rid, len) -> let cl = grammar.idx[rid]
                    add_match!(
                        i,
                        cl,
                        new_match!(Match(cl, i, len, 0, submatch_empty(st)), st),
                        st,
                    )
                end,
            )
        end
        while !isempty(st.q)
            clause = pop!(st.q)
            match[] = 0
            pclause[] = clause
            ii[] = i
            match_clause!(grammar.clauses[clause], pclause, ii, st, match)
            add_match!(i, clause, match[], st)
        end
    end

    st
end
