
"""
$(TYPEDSIGNATURES)

Build a [`Satisfy`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    satisfy(isdigit)
"""
satisfy(f::Function) = Satisfy{Any,Any}(f)

"""
$(TYPEDSIGNATURES)

Build a [`Scan`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    # a rule to match any pair of equal tokens
    scan(m -> (length(m) >= 2 && m[1] == m[2]) ? 2 : 0)
"""
scan(f::Function) = Scan{Any,Any}(f)

"""
$(TYPEDSIGNATURES)

Build a [`Token`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    token('a')
"""
function token(x::T) where {T}
    Token{Any,T}(x)
end

"""
$(TYPEDSIGNATURES)

Build a [`Tokens`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    tokens("keyword")
"""
function tokens(xs::I) where {I}
    Tokens{Any,eltype(I),I}(xs)
end

"""
    end_of_input :: Clause

An [`EndOfInput`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    whole_file = seq(:file_contents, end_of_input)
"""
const end_of_input = EndOfInput{Any,Any}()

"""
    epsilon :: Clause

An [`Epsilon`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    maybe_letter_a = first(token('a'), epsilon)
"""
const epsilon = Epsilon{Any,Any}()

"""
    fail :: Clause

A [`Fail`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

Useful for avoiding rule specification when matching terminals using the
`fast_match` parameter of [`parse`](@ref).


# Example

    seq(:this, :that, fail)  # this rule is effectively disabled
"""
const fail = Fail{Any,Any}()

"""
$(TYPEDSIGNATURES)

Build a [`Seq`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    digit_in_parents = seq(token('('), :digit, token(')'))
"""
seq(args...) = Seq{Any,Any}(collect(args))

"""
$(TYPEDSIGNATURES)

Build a [`First`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    first(:something, :fallback, :fallback2)
"""
first(args...) = First{Any,Any}(collect(args))

"""
$(TYPEDSIGNATURES)

Build a [`NotFollowedBy`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    seq(not_followed_by(tokens(collect("reservedWord"))), :identifier)
"""
function not_followed_by(x::G) where {G}
    NotFollowedBy{G,Any}(x)
end

"""
$(TYPEDSIGNATURES)

Build a [`FollowedBy`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    seq(:digits, followed_by(:whitespace))
"""
function followed_by(x::G) where {G}
    FollowedBy{G,Any}(x)
end

"""
$(TYPEDSIGNATURES)

Build a [`Some`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    some(satisfy(isspace))
"""
function some(x::G) where {G}
    Some{G,Any}(x)
end

"""
$(TYPEDSIGNATURES)

Build a [`Many`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    seq(:quote, many(:quote_contents), :quote)
"""
function many(x::G) where {G}
    Many{G,Any}(x)
end

"""
$(TYPEDSIGNATURES)

Build a [`Tie`](@ref) clause. Translate to strongly typed grammar with [`flatten`](@ref).

# Example

    :alternating_A_and_B => tie(many(seq(:A, :B)))
"""
function tie(x::G) where {G}
    Tie{G,Any}(x)
end

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
                :digits => some(satisfy(isdigit)),
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
                    r in block.args if !(r isa LineNumberNode)
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
- [`scan`](@ref)
- [`token`](@ref)
- [`tokens`](@ref)
- [`epsilon`](@ref) (not a function!)
- [`fail`](@ref) (not a function!)
- [`seq`](@ref)
- [`first`](@ref)
- [`not_followed_by`](@ref)
- [`followed_by`](@ref)
- [`some`](@ref)
- [`many`](@ref)
- [`tie`](@ref)
- [`precedence_cascade`](@ref) (not backed by an actual [`Clause`](@ref)!)

Anonymous nested rules are assigned names that are constructed by `childlabel`
function (gets the original G and and integer with position integer). By
default, `childlabel` concatenates the parent rule name, hyphen, and the
position number to form a `Symbol` (i.e., the default works only in cases when
the rules are labeled by Symbols, and you need to provide your own
implementation for other grammars labeled e.g. by integers or strings).
"""
function flatten(
    rules::Dict{G},
    tokentype::DataType,
    childlabel::Function = (rid, idx) -> Symbol(rid, :-, idx),
) where {G}
    todo = Pair{G,Clause}[r for r in rules]
    res = Dict{G,Clause{G,tokentype}}()

    while !isempty(todo)
        rid, clause = pop!(todo)
        clause isa Clause || throw(DomainError(rid => clause, "unsupported clause type"))
        if haskey(res, rid)
            throw(DomainError(rid, "duplicate rule definition"))
        end
        tmp = rechildren(
            clause,
            tokentype,
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
                        throw(DomainError(ch, "unsupported clause contents"))
                    end
                ) for (i, ch) in enumerate(child_clauses(clause))
            ],
        )
        res[rid] = tmp
    end

    res
end
