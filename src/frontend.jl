
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

Convert a list of rules of increasing associativity to a typical
precedence-handling "failthrough" construction. The result must be
post-processed by [`flatten`](@ref).

Each of the rules is abstracted by "same-associativity" and
"higher-associativity" rules (i.e., it is a binary function), which is used to
correctly link the rules within the precedence group. The first rule is of the
lowest precedence. All rules except the last automatically fallback to the next
rule. The higher-precedence parameter of the last rule is the label of the
first rule.

`label` is a function that generates the label for given `n`-th level of the grammar.

Use [`@precedences`](@ref) for a less verbose construction.

Returns a vector of labeled rules; that must usually be interpolated into the
ruleset.

# Example

    Dict(
        precedence_cascade(
            n -> Symbol(:exprlevel, n),
            (same, next) -> :expr => first(
                :plus => seq(same, token('+'), next),
                :minus => seq(same, token('-'), next),
            ),
            (same, next) -> :times => seq(same, token('*'), next), # left associative
            (same, next) -> :power => seq(next, token('^'), same), # right associative
            (_, restart) -> first(
                :parens => seq(token('('), restart, token(')')),
                :digits => one_or_more(satisfy(isdigit)),
            ),
        )...,
    )
"""
function precedence_cascade(label::Function, levels...)
    n = length(levels)
    precs = label.(1:n)

    return [
        precs[i] => first(levels[i](precs[i], precs[1+i%n]), precs[1+i%n]) for
        i in eachindex(levels)
    ]
end

"""
    @precedences labeller same::Symbol next::Symbol rules

A shortcut macro for [`precedence_cascade`](@ref). Automatically adds lambda
heads with fixed argument names, and splats itself with `...` into the
surrounding environment.

# Example

    Dict(
        @precedences (n->Symbol(:exprlevel, n)) same next begin
            :expr => seq(same, token('+'), next)
            seq(same, token('*'), next)
            first(
                token('x'),
                seq(token('('), next, token(')'))
            )
        end
    )
"""
macro precedences(labeller, same::Symbol, next::Symbol, block)
    block.head == :block ||
        throw(DomainError(block, "@precedences expects a block of grammar rules"))
    esc(
        Expr(
            :...,
            Expr(
                :call,
                precedence_cascade,
                labeller,
                [
                    Expr(:->, Expr(:tuple, same, next), r) for
                    r = block.args if !(r isa LineNumberNode)
                ]...,
            ),
        ),
    )
end


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
- [`precedence_cascade`](@ref) (not backed by an actual [`Clause`](@ref)!)

Anonymous nested rules are assigned names that are constructed by `childlabel`
function (gets the original G and and integer with position integer). By
default, `childlabel` concatenats the parent rule name, hyphen, and the position
number to form a `Symbol` (i.e., the default works only in cases when the rules
are labeled by Symbols, and you need to provide your own implementation for
other grammars labeled e.g. by integers or strings).
"""
function flatten(
    rules::Dict{G},
    childlabel::Function = (rid, idx) -> Symbol(rid, :-, idx),
)::Dict{G,Clause{G}} where {G}
    todo = Pair{G,Clause}[r for r in rules]
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
                        newsym = childlabel(rid, i)
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