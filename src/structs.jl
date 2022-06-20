
#
# Clause types
#

"""
$(TYPEDEF)

Abstract type for all clauses that match a grammar with rule labels of type `G`.

Currently implemented clauses:
- [`Satisfy`](@ref)
- [`TakeN`](@ref)
- [`Token`](@ref)
- [`Tokens`](@ref)
- [`Seq`](@ref)
- [`First`](@ref)
- [`NotFollowedBy`](@ref)
- [`OneOrMore`](@ref)
- [`ZeroOrMore`](@ref)
"""
abstract type Clause{G} end

"""
$(TYPEDEF)

A single terminal. Matches a token from the input stream where the `match`
function returns `true`.

# Fields
$(TYPEDFIELDS)
"""
struct Satisfy{G} <: Clause{G}
    match::Function
end

"""
$(TYPEDEF)

A single terminal. Given the input stream and a position in it, the `match`
function returns the length of the match, or `nothing` if there's no match.

# Fields
$(TYPEDFIELDS)
"""
struct TakeN{G} <: Clause{G}
    match::Function
end

"""
$(TYPEDEF)

A single token equal to `match`.

# Fields
$(TYPEDFIELDS)
"""
struct Token{G} <: Clause{G}
    token::Any #TODO carry the token type in the parameter?
end

"""
$(TYPEDEF)

A series of tokens equal to `match`.

# Fields
$(TYPEDFIELDS)
"""
struct Tokens{G} <: Clause{G}
    tokens::Vector
end

"""
$(TYPEDEF)

An always-succeeding epsilon match.
"""
struct Epsilon{G} <: Clause{G} end

"""
$(TYPEDEF)

Sequence of matches. Empty `Seq` is equivalent to an always-succeeding empty
match, as in [`Epsilon`](@ref).

# Fields
$(TYPEDFIELDS)
"""
struct Seq{G} <: Clause{G}
    children::Vector{G}
end

"""
$(TYPEDEF)

Match the first possibility of several matches. Empty `First` is equivalent to
unconditional failure.

# Fields
$(TYPEDFIELDS)
"""
struct First{G} <: Clause{G}
    children::Vector{G}
end

"""
$(TYPEDEF)

Zero-length match that succeeds if `reserved` does _not_ match at the same position.

# Fields
$(TYPEDFIELDS)
"""
struct NotFollowedBy{G} <: Clause{G}
    reserved::G
end

"""
$(TYPEDEF)

Zero-length match that succeeds if `follow` does match at the same position.

# Fields
$(TYPEDFIELDS)
"""
struct FollowedBy{G} <: Clause{G}
    follow::G
end

"""
$(TYPEDEF)

Greedily matches a sequence of matches, with at least 1 match.

# Fields
$(TYPEDFIELDS)
"""
struct OneOrMore{G} <: Clause{G}
    item::G
end

"""
$(TYPEDEF)

Greedily matches a sequence of matches that can be empty.

# Fields
$(TYPEDFIELDS)
"""
struct ZeroOrMore{G} <: Clause{G}
    item::G
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
struct Grammar{G}
    "Topologically sorted list of rule labels (non-terminals)"
    names::Vector{G}

    "Mapping of rule labels to their indexes in `names`"
    idx::Dict{G,Int}

    "Clauses of the grammar converted to integer labels (and again sorted topologically)"
    clauses::Vector{Clause{Int}}

    "Flags for the rules being able to match on empty string unconditionally"
    can_match_epsilon::Vector{Bool}

    "Which clauses get seeded upon matching of a clause"
    seed_clauses::Vector{Vector{Int}}

    "A summarized list of grammar terminals that are checked against each input letter"
    terminals::Vector{Int}
    # TODO to speed up terminal matching, one could also let the user supply a
    # direct function that produces a G from the input element.
end

"""
$(TYPEDEF)

Index into the memoization table.

# Fields
$(TYPEDFIELDS)
"""
struct MemoKey
    clause::Int
    start_pos::Int
end

@inline Base.isless(a::MemoKey, b::MemoKey) =
    isless((a.start_pos, -a.clause), (b.start_pos, -b.clause))

"""
$(TYPEDEF)

Pikaparser memoization table.
"""
const MemoTable = SortedDict{MemoKey,Int}

"""
$(TYPEDEF)

Internal match representation.

# Fields
$(TYPEDFIELDS)
"""
struct Match
    "Where the match started?"
    pos::Int

    "How long is the match?"
    len::Int

    "Which possibility did we match?"
    option_idx::Int

    "Indexes to the vector of matches. This forms the edges in the match tree."
    submatches::Vector{Int}
end

"""
$(TYPEDEF)

Representation of the parser output.

# Fields
$(TYPEDFIELDS)
"""
struct ParseResult
    "Best matches of grammar rules for each position of the input"
    memo::MemoTable

    "Match tree (folded into a vector)"
    matches::Vector{Match}
end

"""
$(TYPEDEF)

User-facing representation of a [`Match`](@ref).

# Fields
$(TYPEDFIELDS)
"""
struct UserMatch{G}
    "Where the match started?"
    pos::Int

    "How long is the match?"
    len::Int

    "Indexes and rule labels of the matched submatches. This forms the edges in the match tree."
    submatches::Vector{Tuple{Int,G}}
end

#
# Helper types
#

const Maybe{X} = Union{Nothing,X}

const PikaQueue = SortedSet{Int}

"""
$(TYPEDEF)

Intermediate parsing state. The match tree is built in a vector of matches that
grows during the matching, all match indexes point into this vector.

# Fields
$(TYPEDFIELDS)
"""
mutable struct ParserState{G,I}
    grammar::Grammar{G}
    memo::MemoTable
    q::PikaQueue
    matches::Vector{Match}
    input::I
end

"""
$(TYPEDEF)

A shortcut for possibly failed match result index (that points into
[`ParserState`](@ref) field `matches`.
"""
const MatchResult = Maybe{Int}

"""
$(TYPEDEF)

Part of intermediate tree traversing state.

# Fields
$(TYPEDFIELDS)
"""
mutable struct TraverseNode{G}
    parent_idx::Int
    parent_sub_idx::Int
    rule::G
    match::UserMatch
    open::Bool
    subvals::Vector
end
