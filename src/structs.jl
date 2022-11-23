
#
# Clause types
#

"""
$(TYPEDEF)

Abstract type for all clauses that match a grammar with rule labels of type `G`
that match sequences of tokens of type `T`.

Currently implemented clauses:
- [`Satisfy`](@ref)
- [`Scan`](@ref)
- [`Token`](@ref)
- [`Tokens`](@ref)
- [`Epsilon`](@ref)
- [`Fail`](@ref)
- [`Seq`](@ref)
- [`First`](@ref)
- [`NotFollowedBy`](@ref)
- [`FollowedBy`](@ref)
- [`Some`](@ref)
- [`Many`](@ref)
- [`Tie`](@ref)

Often it is better to use convenience functions for rule construction, such as
[`seq`](@ref) or [`token`](@ref); see [`flatten`](@ref) for details.
"""
abstract type Clause{G,T} end

abstract type Terminal{G,T} <: Clause{G,T} end

"""
$(TYPEDEF)

A single terminal. Matches a token from the input stream where the `match`
function returns `true`.

# Fields
$(TYPEDFIELDS)
"""
struct Satisfy{G,T} <: Terminal{G,T}
    match::Function
end

"""
$(TYPEDEF)

A single terminal, possibly made out of multiple input tokens.

Given the input stream and a position in it, the `match` function scans the
input forward and returns the length of the terminal starting at the position.
In case there's no match, it returns a negative value.

# Fields
$(TYPEDFIELDS)
"""
struct Scan{G,T} <: Terminal{G,T}
    match::Function
end

"""
$(TYPEDEF)

A single token equal to `match`.

# Fields
$(TYPEDFIELDS)
"""
struct Token{G,T} <: Terminal{G,T}
    token::T
end

"""
$(TYPEDEF)

A series of tokens equal to `match`.

# Fields
$(TYPEDFIELDS)
"""
struct Tokens{G,T,I} <: Terminal{G,T}
    tokens::I
end

"""
$(TYPEDEF)

An always-succeeding epsilon match.
"""
struct Epsilon{G,T} <: Clause{G,T} end

"""
$(TYPEDEF)

An always-failing match.
"""
struct Fail{G,T} <: Clause{G,T} end

"""
$(TYPEDEF)

Sequence of matches. Empty `Seq` is equivalent to an always-succeeding empty
match, as in [`Epsilon`](@ref).

# Fields
$(TYPEDFIELDS)
"""
struct Seq{G,T} <: Clause{G,T}
    children::Vector{G}
end

"""
$(TYPEDEF)

Match the first possibility of several matches. Empty `First` is equivalent to
unconditional failure.

# Fields
$(TYPEDFIELDS)
"""
struct First{G,T} <: Clause{G,T}
    children::Vector{G}
end

"""
$(TYPEDEF)

Zero-length match that succeeds if `reserved` does _not_ match at the same position.

# Fields
$(TYPEDFIELDS)
"""
struct NotFollowedBy{G,T} <: Clause{G,T}
    reserved::G
end

"""
$(TYPEDEF)

Zero-length match that succeeds if `follow` does match at the same position.

# Fields
$(TYPEDFIELDS)
"""
struct FollowedBy{G,T} <: Clause{G,T}
    follow::G
end

"""
$(TYPEDEF)

Greedily matches a sequence of matches, with at least 1 match.

# Fields
$(TYPEDFIELDS)
"""
struct Some{G,T} <: Clause{G,T}
    item::G
end

"""
$(TYPEDEF)

Greedily matches a sequence of matches that can be empty.

# Fields
$(TYPEDFIELDS)
"""
struct Many{G,T} <: Clause{G,T}
    item::G
end

"""
$(TYPEDEF)

Produces the very same match as the `item`, but concatenates the user views of
the resulting submatches into one big vector (i.e., basically squashing the 2
levels of child matches to a single one.) Useful e.g. for lists with different
initial or final elements.

As a result, the `item` and its immediate children are _not_ going to be
present in the parse tree.

# Fields
$(TYPEDFIELDS)
"""
struct Tie{G,T} <: Clause{G,T}
    tuple::G
end

#
# Main user-facing types
#

"""
$(TYPEDEF)

A representation of the grammar prepared for parsing.

# Fields
$(TYPEDFIELDS)
"""
struct Grammar{G,T}
    "Topologically sorted list of rule labels (non-terminals)"
    names::Vector{G}

    "Mapping of rule labels to their indexes in `names`"
    idx::Dict{G,Int}

    "Clauses of the grammar converted to integer labels (and again sorted topologically)"
    clauses::Vector{Clause{Int,T}}

    "Flags for the rules being able to match on empty string unconditionally"
    can_match_epsilon::Vector{Bool}

    "Which clauses get seeded upon matching of a clause"
    seed_clauses::Vector{Vector{Int}}

    "Sorted indexes of terminal clauses that are checked against each input item."
    terminals::Vector{Int}
end

"""
$(TYPEDEF)

Internal match representation.

# Fields
$(TYPEDFIELDS)
"""
struct Match
    "Which clause has matched here?"
    clause::Int

    "Where the match started?"
    pos::Int

    "How long is the match?"
    len::Int

    "Which possibility (given by the clause) did we match?"
    option_idx::Int

    "Index to the first submatch, the range of submatches spans all the way to the first submatch of the next Match."
    submatches::Int

    "Left child in the memo tree."
    left::Int

    "Right child in the memo tree."
    right::Int

    "Parent in the memo tree."
    parent::Int
end

Match(c::Int, p::Int, l::Int, o::Int, s::Int) = Match(c, p, l, o, s, 0, 0, 0)

Match(
    m::Match;
    clause::Int = m.clause,
    pos::Int = m.pos,
    len::Int = m.len,
    option_idx::Int = m.option_idx,
    submatches::Int = m.submatches,
    left::Int = m.left,
    right::Int = m.right,
    parent::Int = m.parent,
) = Match(clause, pos, len, option_idx, submatches, left, right, parent)

"""
$(TYPEDEF)

User-facing representation of a [`Match`](@ref).

# Fields
$(TYPEDFIELDS)
"""
struct UserMatch{G,S}
    "Which rule ID has matched here?"
    rule::G

    "Where the match started?"
    pos::Int

    "How long is the match?"
    len::Int

    "View of the matched part of the input, usually a `SubArray` or `SubString`."
    view::S

    "Indexes and rule labels of the matched submatches. This forms the edges in the match tree."
    submatches::Vector{Int}
end

#
# Helper types
#

const Maybe{X} = Union{Nothing,X}

mutable struct PikaQueue
    n::UInt
    q::Vector{UInt}
    p::Vector{Bool}
end

"""
$(TYPEDEF)

Intermediate parsing state. The match tree is built in a vector of matches that
grows during the matching, all match indexes point into this vector.

This structure is also a "result" of the parsing, used to reconstruct the match
tree.

# Fields
$(TYPEDFIELDS)
"""
mutable struct ParserState{G,T,I}
    "Copy of the grammar used to parse the input."
    grammar::Grammar{G,T}

    "Queue for rules that should match, used only internally."
    q::PikaQueue

    "Matches, connected by indexes to form a memo table search tree."
    matches::Vector{Match}

    "Root of the memotable search tree (stored in the `matches`)."
    memo_root::Int

    "Children pointers of the matches that form the match tree."
    submatches::Vector{Int}

    "Parser input, used to reconstruct match data."
    input::I
end

"""
$(TYPEDEF)

A match index in [`ParserState`](@ref) field `matches`, or `nothing` if the
match failed.
"""
const MatchResult = Int

"""
$(TYPEDEF)

Part of intermediate tree traversing state.

# Fields
$(TYPEDFIELDS)
"""
mutable struct TraverseNode{G,S}
    parent_idx::Int
    parent_sub_idx::Int
    match::UserMatch{G,S}
    open::Bool
    subvals::Vector
end
