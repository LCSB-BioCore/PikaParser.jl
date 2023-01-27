
#
# Clause implementation
#

isterminal(x::Terminal) = true
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


rechildren(x::Satisfy, t::DataType, v::Vector) = Satisfy{valtype(v),t}(x.match)
rechildren(x::Scan, t::DataType, v::Vector) = Scan{valtype(v),t}(x.match)
rechildren(x::Token, t::DataType, v::Vector) = Token{valtype(v),t}(x.token)
rechildren(x::Tokens, t::DataType, v::Vector) =
    Tokens{valtype(v),t,typeof(x.tokens)}(x.tokens)
rechildren(x::Epsilon, t::DataType, v::Vector) = Epsilon{valtype(v),t}()
rechildren(x::Fail, t::DataType, v::Vector) = Fail{valtype(v),t}()
rechildren(x::Seq, t::DataType, v::Vector) = Seq{valtype(v),t}(v)
rechildren(x::First, t::DataType, v::Vector) = First{valtype(v),t}(v)
rechildren(x::NotFollowedBy, t::DataType, v::Vector) =
    NotFollowedBy{valtype(v),t}(Base.first(v))
rechildren(x::FollowedBy, t::DataType, v::Vector) = FollowedBy{valtype(v),t}(Base.first(v))
rechildren(x::Some, t::DataType, v::Vector) = Some{valtype(v),t}(Base.first(v))
rechildren(x::Many, t::DataType, v::Vector) = Many{valtype(v),t}(Base.first(v))
rechildren(x::Tie, t::DataType, v::Vector) = Tie{valtype(v),t}(Base.first(v))


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
    new.option_idx == old.option_idx ? (new.last > old.last) :
    (new.option_idx < old.option_idx)

better_match_than(::Clause, new::Match, old::Match) = new.last > old.last


can_match_epsilon(x::Union{Satisfy,Scan,Token,Tokens,Fail}, ::Vector{Bool}) = false
can_match_epsilon(x::Epsilon, ::Vector{Bool}) = true
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

function match_terminal(x::Satisfy{G,T}, input::I, pos::Int)::Int where {G,T,I}
    return (pos <= lastindex(input) && x.match(input[pos])) ? pos : prevind(input, pos)
end

function match_terminal(x::Scan{G,T}, input::I, pos::Int)::Int where {G,T,I}
    v = view(input, pos:lastindex(input))
    return pos + max(x.match(v), 0) - firstindex(v)
end

function match_terminal(x::Token{G,T}, input::I, pos::Int)::Int where {G,T,I}
    return x.token == input[pos] ? pos : prevind(input, pos)
end

function match_terminal(x::Tokens{G,T,I}, input::I, pos::Int)::Int where {G,T,I}
    ii = pos
    ie = lastindex(input)
    ti = firstindex(x.tokens)
    te = lastindex(x.tokens)
    while true
        ii <= ie || break
        ti <= te || break
        input[ii] == x.tokens[ti] || break
        ti == te && return ii
        ii = nextind(input, ii)
        ti = nextind(x.tokens, ti)
    end
    return prevind(input, pos)
end

function match_clause!(
    x::TT,
    id::Int,
    pos::Int,
    st::ParserState{G,T,I},
)::MatchResult where {G,T,I,IG,TT<:Terminal{IG,T}}
    last = match_terminal(x, st.input, pos)
    if last < pos
        return 0
    else
        new_match!(Match(id, pos, last, 0, submatch_empty(st)), st)
    end
end

function match_clause!(x::Seq, id::Int, orig_pos::Int, st::ParserState)::MatchResult

    # check first
    pos = orig_pos
    for c in x.children
        mid = lookup_best_match_id!(pos, c, st)
        mid == 0 && return 0
        pos = steplastind(st.input, st.matches[mid].last)
    end

    # allocate submatches
    pos = orig_pos
    last = prevind(st.input, pos)
    seq = submatch_start(st)
    for c in x.children
        mid = lookup_best_match_id!(pos, c, st)
        submatch_record!(st, mid)
        last = st.matches[mid].last
        pos = steplastind(st.input, last)
    end
    new_match!(Match(id, orig_pos, last, 0, seq), st)
end

function match_clause!(x::First, id::Int, pos::Int, st::ParserState)::MatchResult
    res = 0
    for (i, c) in enumerate(x.children)
        mid = lookup_best_match_id!(pos, c, st)
        mid == 0 && continue
        res = new_match!(
            Match(id, pos, st.matches[mid].last, i, submatch_record!(st, mid)),
            st,
        )
        break
    end
    return res
end

function match_clause!(x::FollowedBy, id::Int, pos::Int, st::ParserState)::MatchResult
    mid = lookup_best_match_id!(pos, x.follow, st)
    mid == 0 ? 0 :
    new_match!(Match(id, pos, prevind(st.input, pos), 1, submatch_record!(st, mid)), st)
end

function match_clause!(x::Some, id::Int, pos::Int, st::ParserState)::MatchResult
    mid1 = lookup_best_match_id!(pos, x.item, st)
    mid1 == 0 && return 0
    mid2 = lookup_best_match_id!(steplastind(st.input, st.matches[mid1].last), id, st)
    if mid2 == 0
        new_match!(Match(id, pos, st.matches[mid1].last, 0, submatch_record!(st, mid1)), st)
    else
        new_match!(
            Match(id, pos, st.matches[mid2].last, 1, submatch_record!(st, mid1, mid2)),
            st,
        )
    end
end

function match_clause!(x::Many, id::Int, pos::Int, st::ParserState)::MatchResult
    mid1 = lookup_best_match_id!(pos, x.item, st)
    mid1 == 0 && return match_epsilon!(x, id, pos, st)
    mid2 = lookup_best_match_id!(steplastind(st.input, st.matches[mid1].last), id, st)
    @assert mid2 != 0 "Many did not match, but it should have had!"
    new_match!(
        Match(id, pos, st.matches[mid2].last, 1, submatch_record!(st, mid1, mid2)),
        st,
    )
end

function match_clause!(x::Tie, id::Int, pos::Int, st::ParserState)::MatchResult
    mid = lookup_best_match_id!(pos, x.tuple, st)
    mid == 0 ? 0 :
    new_match!(Match(id, pos, st.matches[mid].last, 1, submatch_record!(st, mid)), st)
end


#
# Epsilon matches
#

match_epsilon!(x::Clause, id::Int, pos::Int, st::ParserState) =
    new_match!(Match(id, pos, prevind(st.input, pos), 0, submatch_empty(st)), st)

function match_epsilon!(x::FollowedBy, id::Int, pos::Int, st::ParserState)
    mid = lookup_best_match_id!(pos, x.follow, st)
    mid == 0 ? 0 :
    new_match!(Match(id, pos, prevind(st.input, pos), 1, submatch_record!(st, mid)), st)
end

function match_epsilon!(x::NotFollowedBy, id::Int, pos::Int, st::ParserState)
    # This might technically cause infinite recursion, byt a cycle of
    # NotFollowedBy clauses is disallowed by the error thrown by
    # can_match_epsilon(::NotFollowedBy, ...)
    mid = lookup_best_match_id!(pos, x.reserved, st)
    mid != 0 ? 0 :
    new_match!(Match(id, pos, prevind(st.input, pos), 0, submatch_empty(st)), st)
end


#
# "User" view of the clauses, for parsetree traversing
#

UserMatch(id::Int, m::Match, submatches::Vector{Int}, st::ParserState) =
    UserMatch(st.grammar.names[id], m.first, m.last, view_match(st, m), submatches)

function user_view(::Clause, id::Int, mid::Int, st::ParserState)
    # generic case
    UserMatch(id, st.matches[mid], Int[], st)
end

function user_view(x::Union{Seq,First,FollowedBy}, id::Int, mid::Int, st::ParserState)
    m = st.matches[mid]
    UserMatch(id, m, collect(submatches(st, mid)), st)
end

function user_view(x::Some, id::Int, mid::Int, st::ParserState)
    items = 1
    m = mid
    while st.matches[m].option_idx == 1
        items += 1
        m = submatches(st, m)[2]
    end
    res = Vector{Int}(undef, items)
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
    items = 0
    m = mid
    while st.matches[m].option_idx == 1
        items += 1
        m = submatches(st, m)[2]
    end
    res = Vector{Int}(undef, items)
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
        return UserMatch(id, m, Int[], st)
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
