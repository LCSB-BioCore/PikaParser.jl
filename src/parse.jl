
function lookup_best_match_id!(
    pos::Int,
    clause::Int,
    st::ParserState{G,T,I},
)::MatchResult where {G,T,I}
    mid = match_find!(st, clause, pos)
    mid != 0 && return mid

    if st.grammar.can_match_epsilon[clause]
        cls = st.grammar.clauses[clause]
        match = 0
        if cls isa FollowedBy{Int,T}
            return match_epsilon!(cls, clause, pos, st)
        elseif cls isa NotFollowedBy{Int,T}
            return match_epsilon!(cls, clause, pos, st)
        else
            return match_epsilon!(cls, clause, pos, st)
        end
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
        if old == 0 ||
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
end

"""
$(TYPEDSIGNATURES)

Take a [`Grammar`](@ref) and an indexable input sequence (typically `Vector` or
`String`), and return a final [`ParserState`](@ref) that contains all matched
grammar productions.

The `input` must be random-indexable (because PikaParsers require a lot of
random indexing). In particular, the type must support Int index computation
with `firstindex`, `lastindex`, `prevind`, `nextind`, and a working `+`.

# Lexing and fast terminal matching

If `fast_match` is specified, the function does not match terminals using the
associated grammar rules, but with a `fast_match` function that reports the
matched terminals via a callback. The function is called exactly once for each
position in `input` in reverse order (i.e., the indexes will start at
`lastindex(input)` and continue using `prevind` all the way to
`firstindex(input)`), which can be utilized by the application for
optimization).  The call parameters consist of the input vector, position in
the input vector, and a "report" function used to send back a clause ID (of
same type as `G` in `typeof(grammar)`) and the length of the terminal matches
that can found at that position. Calls to the reporting function can be
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
necessarily have length 1. Illustratively, the example below may easily break
when processing letters or digits that are longer than 1 byte.

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
        (input, i, match) -> isdigit(input[i]) ? match(:digit, 1) : match(:letter, 1),
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

    # a queue pre-filled with terminal matches (used so that we don't need to refill it manually everytime)
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
                (rid::G, len::Int) -> let cl = grammar.idx[rid]
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
            match = 0
            if cls isa Token{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa Tokens{Int,T,I}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa Satisfy{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa Scan{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa Seq{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa First{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa FollowedBy{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa Many{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa Some{Int,T}
                match = match_clause!(cls, clause, i, st)
            elseif cls isa Tie{Int,T}
                match = match_clause!(cls, clause, i, st)
            else
                match = match_clause!(cls, clause, i, st)
            end
            add_match!(i, clause, match, st)
        end
        i = prevind(input, i)
    end

    st
end

"""
$(TYPEDSIGNATURES)

Greedily find terminals in the input sequence, while avoiding any attempts at
parsing terminals where another terminal was already parsed successfully.
"""
function lex(g::Grammar{G,T}, input::I)::Vector{Vector{Tuple{G,Int}}} where {G,T,I}
    q = PikaQueue(lastindex(input))
    push!(q, 1)
    res = [Vector{Tuple{G,Int}}() for _ = 1:lastindex(input)] # tricky: do not fill()
    while !isempty(q)
        pos = pop!(q)
        for tidx in g.terminals
            m = match_terminal(g.clauses[tidx], input, pos)
            if m >= 0
                push!(res[pos], tuple(g.names[tidx], m))
            end
            if m > 0 && pos + m <= length(input)
                push!(q, pos + m)
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
    fm = (_, i, cb) -> for (rid, len) in lexemes[i]
        cb(rid, len)
    end
    return parse(g, input, fm)
end
