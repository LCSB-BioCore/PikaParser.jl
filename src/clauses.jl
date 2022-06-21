
#
# Clause implementation
#

isterminal(x::Union{Satisfy,TakeN,Token,Tokens}) = true
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

function child_clauses(x::OneOrMore{G})::Vector{G} where {G}
    G[x.item]
end

function child_clauses(x::ZeroOrMore{G})::Vector{G} where {G}
    G[x.item]
end


rechildren(x::Satisfy, v::Vector) = Satisfy{valtype(v)}(x.match)
rechildren(x::TakeN, v::Vector) = TakeN{valtype(v)}(x.match)
rechildren(x::Token, v::Vector) = Token{valtype(v)}(x.token)
rechildren(x::Tokens, v::Vector) = Tokens{valtype(v)}(x.tokens)
rechildren(x::Epsilon, v::Vector) = Epsilon{valtype(v)}()
rechildren(x::Seq, v::Vector) = Seq{valtype(v)}(v)
rechildren(x::First, v::Vector) = First{valtype(v)}(v)
rechildren(x::NotFollowedBy, v::Vector) = NotFollowedBy{valtype(v)}(Base.first(v))
rechildren(x::FollowedBy, v::Vector) = FollowedBy{valtype(v)}(Base.first(v))
rechildren(x::OneOrMore, v::Vector) = OneOrMore{valtype(v)}(Base.first(v))
rechildren(x::ZeroOrMore, v::Vector) = ZeroOrMore{valtype(v)}(Base.first(v))


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

function seeded_by(x::NotFollowedBy{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x) #TODO is this required?
end

function seeded_by(x::FollowedBy{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end

function seeded_by(x::OneOrMore{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end

function seeded_by(x::ZeroOrMore{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end


better_match_than(::First, new::Match, old::Match) =
    new.option_idx == old.option_idx ? (new.len > old.len) :
    (new.option_idx < old.option_idx)

better_match_than(::Clause, new::Match, old::Match) = new.len > old.len


can_match_epsilon(x::Union{Satisfy,TakeN,Token,Tokens}, ::Vector{Bool}) = false
can_match_epsilon(x::Nothing, ::Vector{Bool}) = true
can_match_epsilon(x::Satisfy, ::Vector{Bool}) = false
can_match_epsilon(x::Seq, ch::Vector{Bool}) = all(ch)
can_match_epsilon(x::First, ch::Vector{Bool}) =
    isempty(ch) ? false :
    any(ch[begin:end-1]) ? throw("First with non-terminal epsilon match") : last(ch)
can_match_epsilon(x::NotFollowedBy, ch::Vector{Bool}) =
    ch[1] ? throw("NotFollowedBy epsilon match") : true
can_match_epsilon(x::FollowedBy, ch::Vector{Bool}) = ch[1]
can_match_epsilon(x::OneOrMore, ch::Vector{Bool}) = ch[1]
can_match_epsilon(x::ZeroOrMore, ch::Vector{Bool}) = true


#
# Clause matching
#

function match_clause!(x::Satisfy, ::Int, pos::Int, st::ParserState)::MatchResult
    if x.match(st.input[pos])
        new_match!(Match(pos, 1, 0, []), st)
    end
end

function match_clause!(x::TakeN, ::Int, pos::Int, st::ParserState)::MatchResult
    match_len = x.match(view(st.input, pos:length(st.input)))
    if !isnothing(match_len)
        new_match!(Match(pos, match_len, 0, []), st)
    end
end

function match_clause!(x::Token, ::Int, pos::Int, st::ParserState)::MatchResult
    if st.input[pos] == x.token
        new_match!(Match(pos, 1, 0, []), st)
    end
end

function match_clause!(x::Tokens, ::Int, pos::Int, st::ParserState)::MatchResult
    len = length(x.tokens)
    if pos - 1 + len <= length(st.input) && st.input[pos:pos-1+len] == x.tokens
        new_match!(Match(pos, len, 0, []), st)
    end
end

function match_clause!(x::Seq, ::Int, orig_pos::Int, st::ParserState)::MatchResult
    pos = orig_pos
    seq = Vector{Int}(undef, length(x.children))
    for (i, c) in enumerate(x.children)
        mid = lookup_best_match_id!(MemoKey(c, pos), st)
        if isnothing(mid)
            return nothing
        end

        seq[i] = mid
        pos += st.matches[mid].len
    end
    new_match!(Match(orig_pos, pos - orig_pos, 0, seq), st)
end

function match_clause!(x::First, ::Int, pos::Int, st::ParserState)::MatchResult
    for (i, c) in enumerate(x.children)
        mid = lookup_best_match_id!(MemoKey(c, pos), st)
        if !isnothing(mid)
            return new_match!(Match(pos, st.matches[mid].len, i, [mid]), st)
        end
    end
    nothing
end

function match_clause!(x::NotFollowedBy, ::Int, pos::Int, st::ParserState)::MatchResult
    mid = lookup_best_match_id!(MemoKey(x.reserved, pos), st)
    if isnothing(mid)
        new_match!(Match(pos, 0, 0, []), st)
    else
        nothing
    end
end

function match_clause!(x::FollowedBy, ::Int, pos::Int, st::ParserState)::MatchResult
    mid = lookup_best_match_id!(MemoKey(x.follow, pos), st)
    if isnothing(mid)
        nothing
    else
        new_match!(Match(pos, 0, 1, [mid]), st)
    end
end

function match_clause!(x::OneOrMore, id::Int, pos::Int, st::ParserState)::MatchResult
    mid1 = lookup_best_match_id!(MemoKey(x.item, pos), st)
    isnothing(mid1) && return nothing
    mid2 = lookup_best_match_id!(MemoKey(id, pos + st.matches[mid1].len), st)
    if isnothing(mid2)
        new_match!(Match(pos, st.matches[mid1].len, 0, [mid1]), st)
    else
        new_match!(
            Match(pos, st.matches[mid1].len + st.matches[mid2].len, 1, [mid1, mid2]),
            st,
        )
    end
end

function match_clause!(x::ZeroOrMore, id::Int, pos::Int, st::ParserState)::MatchResult
    mid1 = lookup_best_match_id!(MemoKey(x.item, pos), st)
    if isnothing(mid1)
        return match_epsilon!(x, id, pos, st)
    end
    mid2 = lookup_best_match_id!(MemoKey(id, pos + st.matches[mid1].len), st)
    if isnothing(mid2)
        error(AssertionError("ZeroOrMore did not match, but it should have had!"))
    else
        new_match!(
            Match(pos, st.matches[mid1].len + st.matches[mid2].len, 1, [mid1, mid2]),
            st,
        )
    end
end


match_epsilon!(x::Clause, ::Int, pos::Int, st::ParserState) =
    new_match!(Match(pos, 0, 0, []), st)
#TODO this needs a recursion guard!
match_epsilon!(x::NotFollowedBy, id::Int, pos::Int, st::ParserState) =
    match_clause!(x, id, pos, st)

#
# "User" view of the clauses, for parsetree traversing
#

function user_view(::Clause, parse::ParseResult, mid::Int, d)
    # generic case
    m = parse.matches[mid]
    UserMatch(m.pos, m.len, Tuple{Int,valtype(d)}[])
end

function user_view(x::Seq, parse::ParseResult, mid::Int, d)
    m = parse.matches[mid]
    UserMatch(m.pos, m.len, map(tuple, m.submatches, getindex.(Ref(d), x.children)))
end

function user_view(x::First, parse::ParseResult, mid::Int, d)
    m = parse.matches[mid]
    UserMatch(m.pos, m.len, [(m.submatches[1], d[x.children[m.option_idx]])])
end

function user_view(x::FollowedBy, parse::ParseResult, mid::Int, d)
    m = parse.matches[mid]
    UserMatch(m.pos, m.len, [(m.submatches[1], d[x.follow])])
end

function user_view(x::OneOrMore, parse::ParseResult, mid::Int, d)
    len = 1
    m = mid
    while parse.matches[m].option_idx == 1
        len += 1
        m = parse.matches[m].submatches[2]
    end
    res = Vector{Tuple{Int,valtype(d)}}(undef, len)
    m = mid
    idx = 1
    while parse.matches[m].option_idx == 1
        res[idx] = (parse.matches[m].submatches[1], d[x.item])
        idx += 1
        m = parse.matches[m].submatches[2]
    end
    res[idx] = (parse.matches[m].submatches[1], d[x.item])
    m = parse.matches[mid]
    UserMatch(m.pos, m.len, res)
end

function user_view(x::ZeroOrMore, parse::ParseResult, mid::Int, d)
    len = 0
    m = mid
    while parse.matches[m].option_idx == 1
        len += 1
        m = parse.matches[m].submatches[2]
    end
    res = Vector{Tuple{Int,valtype(d)}}(undef, len)
    m = mid
    idx = 1
    while parse.matches[m].option_idx == 1
        res[idx] = (parse.matches[m].submatches[1], d[x.item])
        idx += 1
        m = parse.matches[m].submatches[2]
    end
    m = parse.matches[mid]
    UserMatch(m.pos, m.len, res)
end
