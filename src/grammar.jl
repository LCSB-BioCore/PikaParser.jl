
"""
$(TYPEDSIGNATURES)

Produce a [`Grammar`](@ref) with rules of type `G` that can be used to
[`parse`](@ref) inputs.

`starts` should collect top-level rules (these will be put at the top of the
topological order of the parsing).

`rules_dict` is a dictionary of grammar clauses.
"""
function make_grammar(
    starts::AbstractVector{G},
    rules_dict::Dict{G,Clause{G}},
)::Grammar{G} where {G}
    rules = collect(rules_dict)
    n_rules = length(rules)
    rule_idx = Dict{G,Int}(map(first, rules) .=> eachindex(rules))

    # compute the topological ordering
    queued = fill(false, n_rules)
    opened = fill(false, n_rules)
    closed = fill(false, n_rules)
    stk = getindex.(Ref(rule_idx), starts)
    queued[stk[1]] = true
    topo_order_idx = fill(0, n_rules)
    last_order = 0
    while !isempty(stk)
        cur = last(stk)
        if !opened[cur]
            opened[cur] = true
            for cc in child_clauses(last(rules[cur]))
                ccidx = rule_idx[cc]
                if !queued[ccidx]
                    push!(stk, ccidx)
                    queued[ccidx] = true
                end
            end
        elseif !closed[cur]
            closed[cur] = true
            pop!(stk)
            last_order += 1
            topo_order_idx[cur] = last_order
        end
    end

    all(closed) || error("some grammar rules not reachable from starts")

    name_idx = Dict{G,Int}(r .=> topo_order_idx[rule_idx[r]] for r in map(first, rules))
    topo_order = invperm(topo_order_idx)

    # Possible problem: tail clause of a cycle that matches epsilon is quite
    # likely not emptiable (unless really lucky), but it might get emptiable if
    # cycle head clause would be emptiable (which is default false).
    #
    # As questions:
    # 1] can there be a whole cycle that matches epsilons? (no)
    # 2] can you generate an empty match of the topologically lowest clause
    #    ("cycling one") based on the fact that the head of the cycle (highest
    #    clause) would generate epsilon? (no idea, but I didn't find a grammar
    #    that could actually generate this problem.)
    #
    # Possible improvement: this only flips stuff to true, there are only
    # finite possible flips -> we can queue the reflips
    emptiable = fill(false, length(topo_order))
    seed = [Set{Int}() for _ in eachindex(topo_order)]

    for (i, idx) in enumerate(topo_order)
        children_emptiable = [
            emptiable[topo_order_idx[rule_idx[cc]]] for
            cc in child_clauses(last(rules[idx]))
        ]
        emptiable[i] = can_match_epsilon(last(rules[idx]), children_emptiable)
        for sp in seeded_by(last(rules[idx]), children_emptiable)
            push!(seed[topo_order_idx[rule_idx[sp]]], i)
        end
    end

    reordered = rules[topo_order]
    Grammar{G}(
        first.(reordered),
        Dict{G,Int}(first.(reordered) .=> eachindex(reordered)),
        translate.(Ref(name_idx), last.(reordered)),
        emptiable,
        collect.(seed),
        [i for (i, r) in enumerate(reordered) if isterminal(last(r))],
    )
end
