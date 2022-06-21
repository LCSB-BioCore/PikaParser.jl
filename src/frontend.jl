
"""
$(TYPEDSIGNATURES)

Build a [`Satisfy`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    satisfy(isdigit)
"""
satisfy(f::Function) = Satisfy{Any}(f)

"""
$(TYPEDSIGNATURES)

Build a [`TakeN`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    # rule to match a pair of equal tokens
    take_n(m -> m[1] == m[2] ? 2 : nothing)
"""
take_n(f::Function) = TakeN{Any}(f)

"""
$(TYPEDSIGNATURES)

Build a [`Token`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    token('a')
"""
token(x) = Token{Any}(x)

"""
$(TYPEDSIGNATURES)

Build a [`Tokens`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    tokens(collect("keyword"))
"""
tokens(xs::Vector) = Tokens{Any}(xs)

"""
    epsilon :: Clause

An [`Epsilon`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    maybe_letter_a = first(token('a'), epsilon)
"""
const epsilon = Epsilon{Any}()

"""
$(TYPEDSIGNATURES)

Build a [`Seq`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    digit_in_parents = seq(token('('), :digit, token(')'))
"""
seq(args...) = Seq(collect(args))

"""
$(TYPEDSIGNATURES)

Build a [`First`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    first(:something, :fallback, :fallback2)
"""
first(args...) = First(collect(args))

"""
$(TYPEDSIGNATURES)

Build a [`NotFollowedBy`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    seq(not_followed_by(tokens(collect("reservedWord"))), :identifier)
"""
not_followed_by(x) = NotFollowedBy(x)

"""
$(TYPEDSIGNATURES)

Build a [`FollowedBy`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    seq(:digits, followed_by(:whitespace))
"""
followed_by(x) = FollowedBy(x)

"""
$(TYPEDSIGNATURES)

Build a [`OneOrMore`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    one_or_more(satisfy(isspace))
"""
one_or_more(x) = OneOrMore(x)

"""
$(TYPEDSIGNATURES)

Build a [`ZeroOrMore`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    seq(:quote, zero_or_more(:quote_contents), :quote)
"""
zero_or_more(x) = ZeroOrMore(x)


"""
$(TYPEDSIGNATURES)

Convert a possibly nested and weakly typed `rules` into a correctly typed and
unnested ruleset, usable in [`make_grammar`](@ref). This allows use of
convenience rule building functions:

- [`satisfy`](@ref)
- [`take_n`](@ref)
- [`token`](@ref)
- [`tokens`](@ref)
- [`epsilon`](@ref) (not a function!)
- [`seq`](@ref)
- [`first`](@ref)
- [`not_followed_by`](@ref)
- [`followed_by`](@ref)
- [`one_or_more`](@ref)
- [`zero_or_more`](@ref)

Anonymous nested rules are assigned names that are constructed by `childname`
function (gets the original G and and integer with position integer). By
default, `childname` concatenats the parent rule name, hyphen, and the position
number to form a `Symbol` (i.e., works only in cases when the rules are indexed
by symbols).
"""
function flatten(
    rules::Dict{G},
    childname::Function = (rid, idx) -> Symbol(rid, :-, idx),
)::Dict{G,Clause{G}} where {G}
    todo = collect(rules)
    res = Dict{G,Clause{G}}()

    while !isempty(todo)
        rid, clause = pop!(todo)
        clause isa Clause || error(DomainError(rid => clause, "unsupported clause type"))
        if haskey(res, rid)
            error(DomainError(rid, "duplicate rule definition"))
        end
        tmp = rechildren(
            clause,
            G[
                (
                    if ch isa G
                        ch
                    elseif ch isa Clause
                        newsym = childname(rid, i)
                        push!(todo, newsym => ch)
                        newsym
                    elseif ch isa Pair && Base.first(ch) isa G && last(ch) isa Clause
                        push!(todo, ch)
                        Base.first(ch)
                    else
                        error(DomainError(ch, "unsupported clause contents"))
                    end
                ) for (i, ch) in enumerate(child_clauses(clause))
            ],
        )
        res[rid] = tmp
    end

    res
end
