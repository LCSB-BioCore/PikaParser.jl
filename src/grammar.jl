
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
    rules_dict::Dict{G,Clause{G,T}};
)::Grammar{G,T} where {G,T}
    rules = collect(rules_dict)
    n_rules = length(rules)
    rule_idx = Dict{G,Int}(map(Base.first, rules) .=> eachindex(rules))

    # compute the topological ordering
    edges = [child_clauses(r) for (_, r) in rules]
    opened = fill(0, n_rules)
    stk = [rule_idx[s] for s in starts]
    topo_order_idx = fill(0, n_rules)
    topo_order = fill(0, n_rules)
    last_order = 0
    while !isempty(stk)
        cur = last(stk)
        if opened[cur] < length(edges[cur])
            opened[cur] += 1
            ccidx = rule_idx[edges[cur][opened[cur]]]
            if opened[ccidx] == 0
                push!(stk, ccidx)
            end
        elseif opened[cur] == length(edges[cur])
            opened[cur] += 1
            pop!(stk)
            last_order += 1
            topo_order[last_order] = cur
            topo_order_idx[cur] = last_order
        end
    end

    # if some grammar rules is unreachable from starts, throw an error with detailed information about what rules are unreachable
    if any(opened .<= 0) # the following code executes only when throwing error, so it doesn't affect runtime efficiency
        reached::Set = Set(starts)
        last_n_reached::Integer = 0
        # uses BFS to compute what rules are reached
        while length(reached) > last_n_reached
            last_n_reached = length(reached)
            for reached_term in reached
                for child in child_clauses(rules_dict[reached_term])
                    if child ∉ reached
                        push!(reached, child)
                    end
                end
            end
        end
        # throw the error with detailed information about what rules are unreachable
        error(
            "The following grammar rules are unreachable from starts:\n" * join(
                setdiff(keys(rules_dict), reached) .|> repr,
                "\n"
            )
        )
    end

    reordered = rules[topo_order]

    # squash clause names to integers
    name_idx = Dict{G,Int}(rid => topo_order_idx[rule_idx[rid]] for (rid, _) in rules)
    clauses = Clause{Int,T}[
        rechildren(cl, T, [name_idx[chcl] for chcl in child_clauses(cl)]) for
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
    q = full_queue(length(clauses))

    while !isempty(q)
        cur = pop!(q)
        # Here we could skip the check if emptiable[cur] is already True, but
        # redoing it actually allows the `can_match_epsilon` implementations to
        # fail in case the grammar is somehow invalid.
        cur_is_emptiable =
            can_match_epsilon(clauses[cur], emptiable[child_clauses(clauses[cur])])
        if !emptiable[cur] && cur_is_emptiable
            # There was a flip, force rechecking.
            emptiable[cur] = cur_is_emptiable
            for pid in parent_clauses[cur]
                push!(q, pid)
            end
        end
    end

    # reconstruct the 'seeds' relationship from 'seeded-by'
    seed_clauses = [Set{Int}() for _ in eachindex(clauses)]
    for (cid, c) in enumerate(clauses)
        for chid in seeded_by(c, emptiable[child_clauses(c)])
            push!(seed_clauses[chid], cid)
        end
    end

    Grammar{G,T}(
        Base.first.(reordered),
        Dict{G,Int}(rid => i for (i, (rid, _)) in enumerate(reordered)),
        clauses,
        emptiable,
        collect.(seed_clauses),
        [i for (i, c) in enumerate(clauses) if isterminal(c)],
    )
end
