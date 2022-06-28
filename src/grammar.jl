
"""
$(TYPEDSIGNATURES)

Produce a [`Grammar`](@ref) with rules of type `G` that can be used to
[`parse`](@ref) inputs.

`starts` should collect top-level rules (these will be put at the top of the
topological order of the parsing).

`rules_dict` is a dictionary of grammar [`Clause`](@ref)s.
"""
function make_grammar(
    starts::AbstractVector{G},
    rules_dict::Dict{G,Clause{G}};
)::Grammar{G} where {G}
    rules = collect(rules_dict)
    n_rules = length(rules)
    rule_idx = Dict{G,Int}(map(Base.first, rules) .=> eachindex(rules))

    # compute the topological ordering
    queued = fill(false, n_rules)
    opened = fill(false, n_rules)
    closed = fill(false, n_rules)
    stk = [rule_idx[s] for s in starts]
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

    topo_order = invperm(topo_order_idx)
    reordered = rules[topo_order]

    # squash clause names to integers
    name_idx = Dict{G,Int}(rid => topo_order_idx[rule_idx[rid]] for (rid, _) in rules)
    clauses = Clause{Int}[
        rechildren(cl, [name_idx[chcl] for chcl in child_clauses(cl)]) for
        (_, cl) in reordered
    ]

    # Flood-fill the "canMatchZeroChar" property (aka emptiable here).
    # This terminates because the total amount of possible flips of the
    # booleans is finite. Because of possible cycles that can match zero chars,
    # we do not use the original "topo-order fill" algorithm but restart a node
    # in case the emptiable status of some of its reverse children changes. For
    # correctness `can_match_epsilon` for each clause must be monotonic in the
    # second parameter.
    emptiable = fill(false, length(clauses))
    parent_clauses = [Set{Int}() for _ in eachindex(clauses)]
    for (cid, c) in enumerate(clauses)
        for chid in child_clauses(c)
            push!(parent_clauses[chid], cid)
        end
    end
    parent_clauses = collect.(parent_clauses)
    q = PikaQueue(eachindex(clauses))

    while !isempty(q)
        cur = pop!(q)
        if emptiable[cur]
            continue
        end
        emptiable[cur] = can_match_epsilon(clauses[cur], emptiable[parent_clauses[cur]])
        if emptiable[cur]
            # there was a flip!
            push!.(Ref(q), parent_clauses[cur])
        end
    end

    # reconstruct the 'seeds' relationship from 'seeded-by'
    seed_clauses = [Set{Int}() for _ in eachindex(clauses)]
    for (cid, c) in enumerate(clauses)
        for chid in seeded_by(c, emptiable[child_clauses(c)])
            push!(seed_clauses[chid], cid)
        end
    end

    Grammar{G}(
        Base.first.(reordered),
        Dict{G,Int}(rid => i for (i, (rid, _)) in enumerate(reordered)),
        clauses,
        emptiable,
        collect.(seed_clauses),
        [i for (i, c) in enumerate(clauses) if isterminal(c)],
    )
end
