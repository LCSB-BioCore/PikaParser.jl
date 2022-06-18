
"""
$(TYPEDSIGNATURES)

Find any possible match of anything starting at input position `pos`.
Preferentially returns the parses that are topologically higher.

If found, returns the [`Match`](@ref) index in [`ParseResult`](@ref), and the
corresponding grammar production rule.
"""
function find_first_parse_at(
    grammar::Grammar{G},
    parse::ParseResult,
    pos::Int,
)::Maybe{Tuple{Int,G}} where {G}
    tk = searchsortedfirst(parse.memo, MemoKey(0, pos - 1))
    tk == pastendsemitoken(parse.memo) && return nothing
    k = deref_key((parse.memo, tk))
    return (k.start_pos, grammar.names[k.clause])
end

"""
$(TYPEDSIGNATURES)

Find the [`Match`](@ref) index in [`ParseResult`](@ref) that matched `rule` at
position `pos`, or `nothing` if there is no such match.
"""
function find_match_at(
    grammar::Grammar{G},
    parse::ParseResult,
    rule::G,
    pos::Int,
)::Maybe{Int} where {G}
    get(parse.memo, MemoKey(grammar.idx[rule], pos), nothing)
end

"""
$(TYPEDSIGNATURES)

Given a [`Match`](@ref) index and the grammar `rule` matched at that index,
recusively depth-first traverse the match tree using functions `open` (called
upon entering a submatch) and `fold` (called upon leaving the submatch).

`open` is given the current grammar rule and the [`UserMatch`](@ref). It should
return a vector of boolean values that tell the traversal which submatches from
the [`UserMatch`](@ref) should be opened. That can be used to skip parsing of
large uninteresting parts of the match tree, such as whitespace or comments. By
default, it opens the whole subtree.

`fold` is given the same current grammar rule and the [`UserMatch`](@ref), and
additionally a vector of folded values from the submatches. The values returned
by `fold` invocations are collected and transferred to higher-level invocations
of `fold`. In case `open` disabled the evaluation of a given submatch,
`nothing` is used as the folded value for the submatch. By default, `fold` just
collects all submatch values and produces a Julia `Expr` AST structure where
rule expansions are represented as function calls.
"""
function traverse_match(
    grammar::Grammar{G},
    parse::ParseResult,
    mid::Int,
    rule::G;
    open::Function = (_, umatch) -> (true for _ in umatch.submatches),
    fold::Function = (rule, umatch, subvals) -> Expr(:call, rule, subvals...),
) where {G}
    stk = TraverseNode{G}[TraverseNode(
        0,
        0,
        rule,
        user_view(grammar.clauses[grammar.idx[rule]], parse, mid, grammar.names),
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
            mask = collect(open(cur.rule, cur.match))
            parent_idx = length(stk)
            # push in reverse order so that it is still evaluated "forward"
            for i in reverse(eachindex(cur.subvals))
                if mask[i]
                    submid, subrule = cur.match.submatches[i]
                    push!(
                        stk,
                        TraverseNode(
                            parent_idx,
                            i,
                            subrule,
                            user_view(
                                grammar.clauses[grammar.idx[subrule]],
                                parse,
                                submid,
                                grammar.names,
                            ),
                            false,
                            Any[],
                        ),
                    )
                end
            end
        else
            val = fold(cur.rule, cur.match, cur.subvals)
            if cur.parent_idx == 0
                return val
            end

            stk[cur.parent_idx].subvals[cur.parent_sub_idx] = val
            pop!(stk)
        end
    end
end
