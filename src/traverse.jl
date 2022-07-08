
"""
$(TYPEDSIGNATURES)

Find the [`Match`](@ref) index in [`ParserState`](@ref) that matched `rule` at
position `pos`, or `nothing` if there is no such match.

Zero-length matches may not be matched at all positions by default; this
function creates the necessary matches in the tables in `st` in case they are
missing. (That is the reason for the `!` label.)
"""
function find_match_at!(st::ParserState{G}, rule::G, pos::Int)::Maybe{Int} where {G}
    lookup_best_match_id!(pos, st.grammar.idx[rule], st)
end

"""
$(TYPEDSIGNATURES)

Get a view of input that corresponds to the given `match`.
"""
view_match(st::ParserState, match::Union{Match,UserMatch}) =
    view(st.input, match.pos:match.pos+match.len-1)

"""
$(TYPEDSIGNATURES)

Get a view of input that corresponds to the match identified by given match ID.
"""
view_match(st::ParserState, mid::Int) = view_match(st, st.matches[mid])

"""
$(TYPEDSIGNATURES)

The default function used as `open` argument in [`traverse_match`](@ref).
"""
default_open(m, p) = (true for _ in m.submatches)

"""
$(TYPEDSIGNATURES)

The default function used as `fold` argument in [`traverse_match`](@ref).
"""
default_fold(m, p, subvals) = Expr(
    :call,
    m.rule,
    (isterminal(p.grammar.clauses[p.grammar.idx[m.rule]]) ? m.view : subvals)...,
)

"""
$(TYPEDSIGNATURES)

Given a [`Match`](@ref) index in [`ParserState`](@ref) `st`, recusively
depth-first traverse the match tree using functions `open` (called upon
entering a submatch) and `fold` (called upon leaving the submatch).

`open` is given a [`UserMatch`](@ref) structure and a reference to the parser
state. It should return a vector of boolean values that tell the traversal
which submatches from the [`UserMatch`](@ref) should be opened. That can be
used to skip parsing of large uninteresting parts of the match tree, such as
whitespace or comments. By default, it opens all submatches, thus the whole
subtree is traversed.

`fold` is given the [`UserMatch`](@ref) structure and a reference to the parser
state, and additionally a vector of folded values from the submatches. The
values returned by `fold` invocations are collected and transferred to
higher-level invocations of `fold`. In case `open` disabled the evaluation of a
given submatch, `nothing` is used as the folded value for the submatch. The
default `open` and `fold` ([`default_open`](@ref), [`default_fold`](@ref)) just
collect all submatch values and produce a Julia `Expr` AST structure where rule
expansions are represented as function calls.
"""
function traverse_match(
    st::ParserState{G,I},
    mid::Int;
    open::Function = default_open,
    fold::Function = default_fold,
) where {G,I}
    stk = TraverseNode{G,eltype(I)}[TraverseNode(
        0,
        0,
        user_view(
            st.grammar.clauses[st.matches[mid].clause],
            st.matches[mid].clause,
            mid,
            st,
        ),
        false,
        Any[],
    )]

    while true
        # note: `while true` looks a bit crude, right?. Isn't there an iterator
        # that would generate nothing forever, ideally called `forever`?
        cur = last(stk)
        if !cur.open
            cur.open = true
            cur.subvals = Any[nothing for _ in eachindex(cur.match.submatches)]
            mask = collect(open(cur.match, st))
            parent_idx = length(stk)
            # push in reverse order so that it is still evaluated "forward"
            for i in reverse(eachindex(cur.subvals))
                if mask[i]
                    submid = cur.match.submatches[i]
                    clause = st.matches[submid].clause
                    push!(
                        stk,
                        TraverseNode(
                            parent_idx,
                            i,
                            user_view(st.grammar.clauses[clause], clause, submid, st),
                            false,
                            Any[],
                        ),
                    )
                end
            end
        else
            val = fold(cur.match, st, cur.subvals)
            if cur.parent_idx == 0
                return val
            end

            stk[cur.parent_idx].subvals[cur.parent_sub_idx] = val
            pop!(stk)
        end
    end
end
