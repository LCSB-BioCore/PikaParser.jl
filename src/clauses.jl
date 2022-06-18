
#
# Clause implementation
#

isterminal(x::Terminal) = true
isterminal(x::Clause) = false


function child_clauses(x::Terminal{G})::Vector{G} where {G}
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

function child_clauses(x::OneOrMore{G})::Vector{G} where {G}
    G[x.match]
end


translate(d, x::Terminal) = Terminal{valtype(d)}(x.match)
translate(d, x::Seq) = Seq(getindex.(Ref(d), x.children))
translate(d, x::First) = First(getindex.(Ref(d), x.children))
translate(d, x::NotFollowedBy) = NotFollowedBy(d[x.reserved])
translate(d, x::OneOrMore) = OneOrMore(d[x.match])


function seeded_by(x::Terminal{G}, ::Vector{Bool})::Vector{G} where {G}
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
    child_clauses(x)
end

function seeded_by(x::OneOrMore{G}, ::Vector{Bool})::Vector{G} where {G}
    child_clauses(x)
end

better_match_than(::First, new::Match, old::Match) =
    new.option_idx == old.option_idx ? (new.len > old.len) :
    (new.option_idx < old.option_idx)

better_match_than(::Clause, new::Match, old::Match) = new.len > old.len

can_match_epsilon(x::Terminal, ::Vector{Bool}) = false
can_match_epsilon(x::Seq, ch::Vector{Bool}) = all(ch)
can_match_epsilon(x::First, ch::Vector{Bool}) =
    isempty(ch) ? false :
    any(ch[begin:end-1]) ? throw("First with non-terminal epsilon match") : last(ch)
can_match_epsilon(x::NotFollowedBy, ch::Vector{Bool}) =
    ch[1] ? throw("NotFollowedBy epsilon match") : true
can_match_epsilon(x::OneOrMore, ch::Vector{Bool}) = ch[1]

#
# Clause matching
#

function match_clause!(x::Terminal, ::Int, pos::Int, st::ParserState)::MatchResult
    if x.match(st.input[pos])
        new_match!(Match(pos, 1, 0, []), st)
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

function match_clause!(x::OneOrMore, id::Int, pos::Int, st::ParserState)::MatchResult
    mid1 = lookup_best_match_id!(MemoKey(x.match, pos), st)
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


match_epsilon!(x::Clause, ::Int, pos::Int, st::ParserState) =
    new_match!(Match(pos, 0, 0, []), st)
match_epsilon!(x::NotFollowedBy, id::Int, pos::Int, st::ParserState) =
    match_clause!(x, id, pos, st)

#
# "User" view of the clauses, for parsetree traversing
#

function user_view(::Terminal, parse::ParseResult, mid::Int, d)
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

function user_view(::NotFollowedBy, ::ParseResult, ::Int, _)
    nothing
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
        res[idx] = (parse.matches[m].submatches[1], d[x.match])
        idx += 1
        m = parse.matches[m].submatches[2]
    end
    res[idx] = (parse.matches[m].submatches[1], d[x.match])
    m = parse.matches[mid]
    UserMatch(m.pos, m.len, res)
end
