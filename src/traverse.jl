
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
) where G
    rid = grammar.idx[rule]

    # TODO flatten the recursion here

    v = user_view(grammar.clauses[rid], parse, mid, grammar.names)
    isnothing(v) && return nothing

    fold(
        rule,
        v,
        [
            proceed ? traverse_match(grammar, parse, cmid, crule; open, fold) : nothing for
            (proceed, (cmid, crule)) in zip(open(rule, v), v.submatches)
        ],
    )
end
