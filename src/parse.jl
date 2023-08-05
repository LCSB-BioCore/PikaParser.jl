
steplastind(data, last) = last > lastindex(data) ? lastindex(data) : nextind(data, last)

function lookup_best_match_id!(
    pos::Int,
    clause::Int,
    st::ParserState{G,T,I},
)::MatchResult where {G,T,I}
    mid = match_find!(st, clause, pos)
    mid != 0 && return mid

    if st.grammar.can_match_epsilon[clause]
        cls = st.grammar.clauses[clause]
        if cls isa FollowedBy{Int,T}
            return match_epsilon!(cls, clause, pos, st)
        elseif cls isa NotFollowedBy{Int,T}
            return match_epsilon!(cls, clause, pos, st)
        elseif cls isa EndOfInput{Int,T}
            return match_epsilon!(cls, clause, pos, st)
        elseif cls isa Epsilon{Int,T}
            return match_epsilon!(cls, clause, pos, st)
        elseif cls isa Many{Int,T}
            return match_epsilon!(cls, clause, pos, st)
        else
            # This is reached rarely in corner cases
            return match_epsilon!(cls, clause, pos, st)
        end
    end

    return 0
end

function new_match!(match::Match, st::ParserState)
    updated = false

    best = match_find!(st, match.clause, match.first)

    if best == 0 ||
       better_match_than(st.grammar.clauses[match.clause], match, st.matches[best])
        push!(st.matches, match)
        best = lastindex(st.matches)
        match_insert!(st, best)
        updated = true
    else
        # if we didn't record this match, we need to kill the submatches that
        # were allocated prior to calling new_match!
        submatch_rollback!(st, match.submatches)
    end

    for seed in st.grammar.seed_clauses[match.clause]
        if updated || st.grammar.can_match_epsilon[seed]
            push!(st.q, seed)
        end
    end

    return best
end

"""
$(TYPEDSIGNATURES)

Take a [`Grammar`](@ref) and an indexable input sequence (typically `Vector` or
`String`), and return a final [`ParserState`](@ref) that contains all matched
grammar productions.

The `input` must be random-indexable (because PikaParsers require a lot of
random indexing) using Int indexes, must support `firstindex`, `lastindex`,
`prevind`, `nextind`, index arithmetics with `+` and `-`, and indexes in
`view`s must be the same as in original container except for a constant offset.

# Lexing and fast terminal matching

If `fast_match` is specified, the function does not match terminals using the
associated grammar rules, but with a `fast_match` function that reports the
matched terminals via a callback. The function is called exactly once for each
position in `input` in reverse order (i.e., the indexes will start at
`lastindex(input)` and continue using `prevind` all the way to
`firstindex(input)`), which can be utilized by the application for
optimization. The call parameters consist of the input vector, position in
the input vector, and a "report" function used to send back a clause ID (of
same type as `G` in `typeof(grammar)`) and the last item of the terminal match
that can starts at that position. Calls to the reporting function can be
repeated if more terminal types match. Terminals not reported by the calls to
`fast_match` will not be matched.

For complicated grammars, this may be much faster than having the parser to try
matching all terminal types at each position.

If your grammar does not contain dangerous or highly surprising kinds of
terminals (in particular, it can be scanned greedily left-to-right), you may
use [`parse_lex`](@ref) to run a reasonable terminal-only lexing step, which is
then automatically used as a basis for fast matching.

# Caveats

Take care when indexing `String`s. With UTF-8, not all codepoints may
necessarily have length 1.

If unsure, you may always `collect` the strings to vectors of `Char`s
(basically converting to UTF-32), where each character occupies precisely one
index.

# Results

Use [`find_match_at!`](@ref) to extract matches from [`ParserState`](@ref).

Pika parsing never really fails. Instead, in case when the grammar rule is not
matched in the input, the expected rule match match is either not going to be
found at the starting position with [`find_match_at!`](@ref), or it will not
span the whole input.

# Example

    parse(
        g,
        "abcde123",
        (input, i, match) -> isdigit(input[i]) ? match(:digit, i) : match(:letter, i),
    )

"""
function parse(
    grammar::Grammar{G,T},
    input::I,
    fast_match = nothing,
)::ParserState{G,T,I} where {G,T,I}
    st = ParserState{G,T,I}(
        grammar,
        PikaQueue(length(grammar.clauses)),
        Match[],
        0,
        Int[],
        input,
    )

    # a "master" queue pre-filled with all terminal matches
    # (so that we don't need to refill it manually everytime)
    terminal_q = PikaQueue(length(grammar.clauses))
    reset!(terminal_q, grammar.terminals)

    i = lastindex(input)
    while i >= firstindex(input)
        if isnothing(fast_match)
            reset!(st.q, terminal_q)
        else
            fast_match(
                input,
                i,
                (rid::G, last::Int) -> let cl = grammar.idx[rid]
                    new_match!(Match(cl, i, last, 0, submatch_empty(st)), st)
                end,
            )
        end
        while !isempty(st.q)
            clause = pop!(st.q)

            # For whatever reason, Julia inference is unable to find that the
            # arguments of match_clause! are compatible and causes an ugly
            # amount of allocation on the calls (basically wrapping Int64s).
            # Splitting the cases manually prevents that to some (relatively
            # large) extent. As another optimization, one can pass the integers
            # around in Ref (as "output arguments"), which prevents wrapping of
            # the output integer in case the inference can't guess that it's
            # going to be an integer. (This was the case previously when this
            # returned Maybe{Int}.)
            #
            # This is not optimal by far but I don't really like the "solution"
            # with Ref{}s. Let's hope that there will be a solution to force
            # the type inference to find that this dispatch is in fact very
            # regular and almost trivial.
            cls = grammar.clauses[clause]
            if cls isa Token{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa Tokens{Int,T,I}
                match_clause!(cls, clause, i, st)
            elseif cls isa Satisfy{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa Scan{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa Seq{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa First{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa FollowedBy{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa Many{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa Some{Int,T}
                match_clause!(cls, clause, i, st)
            elseif cls isa Tie{Int,T}
                match_clause!(cls, clause, i, st)
            else
                # Fallback (execution shouldn't reach here)
                match_clause!(cls, clause, i, st)
            end
            # Shame ends here.
        end
        i = prevind(input, i)
    end

    st
end

"""
$(TYPEDSIGNATURES)

Greedily find terminals in the input sequence. For performance and uniqueness
purposes, terminals are only looked for at stream indexes that follow the final
indexes of terminals found previously. That allows the lexing process to skip
many redundant matches that could not ever be found by the grammar.

As a main outcome, this prevents the typical pika-parser behavior when matching
sequences using [`many`](@ref), where e.g. an identifier like `abcd` also
produces redundant (and often invalid) matches for `bcd`, `cd` and `d`.
Colaterally, greedy lexing also creates less tokens in the match table, which
results in faster parsing.

To produce good terminal matches quickly, use [`scan`](@ref).

In a typical use, this function is best called indirectly via
[`parse_lex`](@ref).
"""
function lex(g::Grammar{G,T}, input::I)::Vector{Vector{Tuple{G,Int}}} where {G,T,I}
    q = PikaQueue(lastindex(input))

    # tricky: both use of eachindex() and of fill() are actually wrong here
    res = [Vector{Tuple{G,Int}}() for _ = firstindex(input):lastindex(input)]
    firstindex(input) <= lastindex(input) && push!(q, firstindex(input))

    while !isempty(q)
        pos = pop!(q)
        for tidx in g.terminals
            mlast = match_terminal(g.clauses[tidx], input, pos)
            if mlast >= pos
                push!(res[pos], tuple(g.names[tidx], mlast))
            end
            nxt = steplastind(input, mlast)
            if nxt > pos && nxt <= lastindex(input)
                push!(q, nxt)
            end
        end
    end
    res
end

"""
$(TYPEDSIGNATURES)

Use [`lex`](@ref) to greedily produce lexemes for a given grammar, and run the
parsing atop the result.

While this will produce a different (much more sparse) parsing table and the
resulting parse tree may be different from the "full" parse, having the lower
levels of the parse tree efficiently pre-chewed vastly simplifies the overall
parsing, thus saving a lot of time.
"""
function parse_lex(g::Grammar{G,T}, input::I)::ParserState{G,T,I} where {G,T,I}
    lexemes = lex(g, input)
    fm = (_, i, cb) -> for (rid, last) in lexemes[i]
        cb(rid, last)
    end
    return parse(g, input, fm)
end
