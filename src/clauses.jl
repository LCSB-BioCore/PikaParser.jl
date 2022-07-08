
#
# Clause implementation
#

isterminal(x::Union{Satisfy,Scan,Token,Tokens}) = true
isterminal(x::Clause) = false


function child_clauses(x::Clause{G})::Vector{G} where {G}
    # generic case
    G[]
end

function child_clauses(x::Seq{G})::Vector{G} where {G}
    x.children
end

function child_clauses(x::First{G})::Vector{G} where {G}
    x.children
end

function child_clauses(x::NotFollowedBy{G})::Vector{G} where {G}
    G[x.reserved]
end

function child_clauses(x::FollowedBy{G})::Vector{G} where {G}
    G[x.follow]
end

function child_clauses(x::Some{G})::Vector{G} where {G}
    G[x.item]
end

function child_clauses(x::Many{G})::Vector{G} where {G}
    G[x.item]
end

function child_clauses(x::Tie{G})::Vector{G} where {G}
    G[x.tuple]
end


rechildren(x::Satisfy, v::Vector) = Satisfy{valtype(v)}(x.match)
rechildren(x::Scan, v::Vector) = Scan{valtype(v)}(x.match)
rechildren(x::Token, v::Vector) = Token{valtype(v)}(x.token)
rechildren(x::Tokens, v::Vector) = Tokens{valtype(v)}(x.tokens)
rechildren(x::Epsilon, v::Vector) = Epsilon{valtype(v)}()
rechildren(x::Fail, v::Vector) = Fail{valtype(v)}()
rechildren(x::Seq, v::Vector) = Seq{valtype(v)}(v)
rechildren(x::First, v::Vector) = First{valtype(v)}(v)
rechildren(x::NotFollowedBy, v::Vector) = NotFollowedBy{valtype(v)}(Base.first(v))
rechildren(x::FollowedBy, v::Vector) = FollowedBy{valtype(v)}(Base.first(v))
rechildren(x::Some, v::Vector) = Some{valtype(v)}(Base.first(v))
rechildren(x::Many, v::Vector) = Many{valtype(v)}(Base.first(v))
rechildren(x::Tie, v::Vector) = Tie{valtype(v)}(Base.first(v))


function seeded_by(x::Clause{G}, ::Vector{Bool})::Vector{G} where {G}
    # generic case
    G[]
end

function seeded_by(x::Seq{G}, ch::Vector{Bool})::Vector{G} where {G}
    first_nonempty = all(ch) ? length(ch) : findfirst(!, ch)
    x.children[begin:first_nonempty]
end

function seeded_by(x::First{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end

function seeded_by(x::FollowedBy{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end

function seeded_by(x::Some{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end

function seeded_by(x::Many{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end

function seeded_by(x::Tie{G}, ch::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end


better_match_than(::First, new::Match, old::Match) =
    new.option_idx == old.option_idx ? (new.len > old.len) :
    (new.option_idx < old.option_idx)

better_match_than(::Clause, new::Match, old::Match) = new.len > old.len


can_match_epsilon(x::Union{Satisfy,Scan,Token,Tokens}, ::Vector{Bool}) = false
can_match_epsilon(x::Epsilon, ::Vector{Bool}) = true
can_match_epsilon(x::Fail, ::Vector{Bool}) = false
can_match_epsilon(x::Seq, ch::Vector{Bool}) = all(ch)
can_match_epsilon(x::First, ch::Vector{Bool}) =
    isempty(ch) ? false :
    any(ch[begin:end-1]) ? error("First with non-terminal epsilon match") : last(ch)
can_match_epsilon(x::NotFollowedBy, ch::Vector{Bool}) =
    ch[1] ? error("NotFollowedBy epsilon match") : true
can_match_epsilon(x::FollowedBy, ch::Vector{Bool}) = ch[1]
can_match_epsilon(x::Some, ch::Vector{Bool}) = ch[1]
can_match_epsilon(x::Many, ch::Vector{Bool}) = true
can_match_epsilon(x::Tie, ch::Vector{Bool}) = ch[1]


#
# Clause matching
#

function match_clause!(x::Satisfy, id::Int, pos::Int, st::ParserState)::MatchResult
    if x.match(st.input[pos])
        new_match!(Match(id, pos, 1, 0, submatch_empty(st)), st)
    end
end

function match_clause!(x::Scan, id::Int, pos::Int, st::ParserState)::MatchResult
    match_len = x.match(view(st.input, pos:length(st.input)))
    if !isnothing(match_len)
        new_match!(Match(id, pos, match_len, 0, submatch_empty(st)), st)
    end
end

function match_clause!(x::Token, id::Int, pos::Int, st::ParserState)::MatchResult
    if st.input[pos] == x.token
        new_match!(Match(id, pos, 1, 0, submatch_empty(st)), st)
    end
end

function match_clause!(x::Tokens, id::Int, pos::Int, st::ParserState)::MatchResult
    len = length(x.tokens)
    if pos - 1 + len <= length(st.input) && st.input[pos:pos-1+len] == x.tokens
        new_match!(Match(id, pos, len, 0, submatch_empty(st)), st)
    end
end

function match_clause!(x::Seq, id::Int, orig_pos::Int, st::ParserState)::MatchResult

    # check first
    pos = orig_pos
    for c in x.children
        mid = lookup_best_match_id!(pos, c, st)
        isnothing(mid) && return nothing
        pos += st.matches[mid].len
    end

    # allocate submatches
    pos = orig_pos
    seq = submatch_start(st)
    for c in x.children
        mid = lookup_best_match_id!(pos, c, st)
        submatch_record!(st, mid)
        pos += st.matches[mid].len
    end
    new_match!(Match(id, orig_pos, pos - orig_pos, 0, seq), st)
end

function match_clause!(x::First, id::Int, pos::Int, st::ParserState)::MatchResult
    for (i, c) in enumerate(x.children)
        mid = lookup_best_match_id!(pos, c, st)
        if !isnothing(mid)
            return new_match!(
                Match(id, pos, st.matches[mid].len, i, submatch_record!(st, mid)),
                st,
            )
        end
    end
    nothing
end

function match_clause!(x::FollowedBy, id::Int, pos::Int, st::ParserState)::MatchResult
    mid = lookup_best_match_id!(pos, x.follow, st)
    if isnothing(mid)
        nothing
    else
        new_match!(Match(id, pos, 0, 1, submatch_record!(st, mid)), st)
    end
end

function match_clause!(x::Some, id::Int, pos::Int, st::ParserState)::MatchResult
    mid1 = lookup_best_match_id!(pos, x.item, st)
    isnothing(mid1) && return nothing
    mid2 = lookup_best_match_id!(pos + st.matches[mid1].len, id, st)
    if isnothing(mid2)
        new_match!(Match(id, pos, st.matches[mid1].len, 0, submatch_record!(st, mid1)), st)
    else
        new_match!(
            Match(
                id,
                pos,
                st.matches[mid1].len + st.matches[mid2].len,
                1,
                submatch_record!(st, mid1, mid2),
            ),
            st,
        )
    end
end

function match_clause!(x::Many, id::Int, pos::Int, st::ParserState)::MatchResult
    mid1 = lookup_best_match_id!(pos, x.item, st)
    if isnothing(mid1)
        return match_epsilon!(x, id, pos, st)
    end
    mid2 = lookup_best_match_id!(pos + st.matches[mid1].len, id, st)
    isnothing(mid2) && error("Many did not match, but it should have had!")
    new_match!(
        Match(
            id,
            pos,
            st.matches[mid1].len + st.matches[mid2].len,
            1,
            submatch_record!(st, mid1, mid2),
        ),
        st,
    )
end

function match_clause!(x::Tie, id::Int, pos::Int, st::ParserState)::MatchResult
    mid = lookup_best_match_id!(pos, x.tuple, st)
    isnothing(mid) && return nothing
    new_match!(Match(id, pos, st.matches[mid].len, 1, submatch_record!(st, mid)), st)
end



match_epsilon!(x::Clause, id::Int, pos::Int, st::ParserState) =
    new_match!(Match(id, pos, 0, 0, submatch_empty(st)), st)

function match_epsilon!(x::NotFollowedBy, id::Int, pos::Int, st::ParserState)
    # This might technically cause infinite recursion, byt a cycle of
    # NotFollowedBy clauses is disallowed by the error thrown by
    # can_match_epsilon(::NotFollowedBy, ...)
    mid = lookup_best_match_id!(pos, x.reserved, st)
    if isnothing(mid)
        new_match!(Match(id, pos, 0, 0, submatch_empty(st)), st)
    else
        nothing
    end
end


#
# "User" view of the clauses, for parsetree traversing
#

function UserMatch(
    id::Int,
    m::Match,
    submatches::Vector{Int},
    st::ParserState{G,I},
) where {G,I}
    UserMatch{G,eltype(I)}(
        st.grammar.names[id],
        m.pos,
        m.len,
        view_match(st, m),
        submatches,
    )
end

function user_view(::Clause, id::Int, mid::Int, st::ParserState)
    # generic case
    UserMatch(id, st.matches[mid], Int[], st)
end

function user_view(x::Union{Seq,First,FollowedBy}, id::Int, mid::Int, st::ParserState)
    m = st.matches[mid]
    UserMatch(id, m, collect(submatches(st, mid)), st)
end

function user_view(x::Some, id::Int, mid::Int, st::ParserState)
    len = 1
    m = mid
    while st.matches[m].option_idx == 1
        len += 1
        m = submatches(st, m)[2]
    end
    res = Vector{Int}(undef, len)
    m = mid
    idx = 1
    while st.matches[m].option_idx == 1
        res[idx] = submatches(st, m)[1]
        idx += 1
        m = submatches(st, m)[2]
    end
    res[idx] = submatches(st, m)[1]
    UserMatch(id, st.matches[mid], res, st)
end

function user_view(x::Many, id::Int, mid::Int, st::ParserState)
    len = 0
    m = mid
    while st.matches[m].option_idx == 1
        len += 1
        m = submatches(st, m)[2]
    end
    res = Vector{Int}(undef, len)
    m = mid
    idx = 1
    while st.matches[m].option_idx == 1
        res[idx] = submatches(st, m)[1]
        idx += 1
        m = submatches(st, m)[2]
    end
    UserMatch(id, st.matches[mid], res, st)
end

function user_view(x::Tie, id::Int, mid::Int, st::ParserState)
    m = st.matches[mid]
    if m.option_idx == 0
        # epsilon match
        return UserMatch(id, m.pos, m.len, [], st)
    end

    tmid = submatches(st, mid)[1]
    tm = st.matches[tmid]

    ccmids = Int[]
    for cmid in user_view(st.grammar.clauses[tm.clause], tm.clause, tmid, st).submatches
        cl = st.matches[cmid].clause
        for ccmid in user_view(st.grammar.clauses[cl], cl, cmid, st).submatches
            push!(ccmids, ccmid)
        end
    end

    UserMatch(id, m, ccmids, st)
end
