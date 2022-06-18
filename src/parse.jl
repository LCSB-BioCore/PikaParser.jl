
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

Use [`find_first_parse_at`](@ref) or [`find_match_at`](@ref) to extract matches
from [`ParseResult`](@ref).

Pika parsing never really fails. Instead, in case when the grammar rule is not
matched in the input, the expected rule match match is either not going to be
found at the starting position with [`find_match_at`](@ref), or it will not
span the whole input.
"""
function parse(grammar::Grammar, input::AbstractVector)::ParseResult
    st = ParserState(grammar, MemoTable(), PikaQueue(), Match[], input)
    sizehint!(st.matches, length(input)) # hopefully avoids a painful part of the overhead

    for i in reverse(eachindex(input))
        push!(st.q, grammar.terminals...)
        while !isempty(st.q)
            clause = pop!(st.q)
            match = match_clause!(grammar.clauses[clause], clause, i, st)
            add_match!(MemoKey(clause, i), match, st)
        end
    end

    return ParseResult(st.memo, st.matches)
end
