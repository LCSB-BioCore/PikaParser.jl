
# # Example: Faster parsing with lexers

# One disadvantage of pika-style parsers is the large amount of redundant
# intermediate matches that are produced in the right-to-left parsing process.
# These generally pollute the match table and cause inefficiency.
#
# PikaParser supports greedily pre-lexing the parser input using the terminals
# in the grammar, which allows you to produce much more precise terminal
# matches, thus also more compact match table, and, in result, much **faster**
# and more robust parser.
#
# In this example, we simply rewrite the Scheme grammar from [the Scheme
# tutorial](scheme.md) to use [`PikaParser.scan`](@ref) (which allows you to
# match many interesting kinds of tokens quickly) and then
# [`PikaParser.parse_lex`](@ref) (which runs the greedy lexing and uses the
# result for more efficient parsing).
#
# As the main change, we removed the "simple" matches of `:digit` and `:letter`
# from the grammar, and replaced them with manual matchers of whole tokens.
#
# ## Writing scanners
#
# First, let's make a very useful helper function that lets us convert any
# `Char`-matching function into a scanner. This neatens the grammar code later.
#
# When constructing the scanner functions, remember that it is important to use
# the overloaded indexing functions (`nextind`, `prevind`, `firstindex`,
# `lastindex`) instead of manually computing the integer indexes. Consider what
# happens with Unicode strings if you try to get an index like `"kůň"[3]`!
# Compute indexes manually only if you are *perfectly* certain that the input
# indexing is flat.

takewhile1(f) = (input) -> begin
    isempty(input) && return 0
    for i in eachindex(input)
        if !f(input[i])
            return prevind(input, i)
        end
    end
    return lastindex(input)
end;

# The situation for matching `:ident` is a little more complicated -- we need a
# different match on the first letter and there are extra characters to think
# about. So we just make a specialized function for that:

function take_ident(input)
    isempty(input) && return 0
    i = firstindex(input)
    isletter(input[i]) || return 0
    i = nextind(input, i)
    while i <= lastindex(input)
        c = input[i]
        if !(isletter(c) || isdigit(c) || c == '-')
            return prevind(input, i)
        end
        i = nextind(input, i)
    end
    return lastindex(input)
end;

# ## Using scanners in a grammar
#
# The grammar becomes slightly simpler than in the original version:

import PikaParser as P

rules = Dict(
    :ws => P.first(:spaces => P.scan(takewhile1(isspace)), P.epsilon),
    :popen => P.seq(P.token('('), :ws),
    :pclose => P.seq(P.token(')'), :ws),
    :sexpr => P.seq(:popen, :insexpr => P.many(:scheme), :pclose),
    :scheme => P.seq(
        :basic => P.first(
            :number => P.seq(P.scan(takewhile1(isdigit)), P.not_followed_by(:ident)),
            :ident => P.scan(take_ident),
            :sexpr,
        ),
        :ws,
    ),
    :top => P.seq(:ws, :sexpr), #support leading blanks
);

# ## Using the scanners for lexing the input
#
# Let's try the lexing on the same input as in the Scheme example:

input = """
(plus 1 2 3)
(minus 1 2(plus 3 2)  ) woohoo extra parenthesis here )
(complex
  id3nt1f13r5 αβγδ भरत kůň)
(invalid 1d3n7)
(something
  1
  2
  valid)
(straight (out (missing(parenthesis error))
(apply (make-function) (make-data))
""";
grammar = P.make_grammar([:top], P.flatten(rules, Char));

P.lex(grammar, input)

# The result is a vector of possible terminals that can be matched at given
# input positions. As a minor victory, you may see that no terminals are
# matched inside the initial `plus` token.
#
# Now, the lexed input could be used via the argument `fast_match` of
# [`PikaParser.parse`](@ref), but usually it is much simpler to have the
# combined function [`PikaParser.parse_lex`](@ref) do everything:

p = P.parse_lex(grammar, input);

# The rest is now essentially same as with the [previous Scheme example](scheme.md):

fold_scheme(m, p, s) =
    m.rule == :number ? parse(Int, m.view) :
    m.rule == :ident ? Symbol(m.view) :
    m.rule == :insexpr ? Expr(:call, :S, s...) :
    m.rule == :sexpr ? s[2] : m.rule == :top ? s[2] : length(s) > 0 ? s[1] : nothing;

next_pos = 1
while next_pos <= lastindex(p.input)
    global next_pos
    pos = next_pos
    mid = 0
    while pos <= lastindex(p.input) # try to find a match
        mid = P.find_match_at!(p, :top, pos)
        mid != 0 && break
        pos = nextind(p.input, pos)
    end
    pos > next_pos && # if we skipped something, report it
        println("Problems with: $(p.input[next_pos:prevind(p.input, pos)])")
    if mid == 0
        break # if we skipped all the way to the end, quit
    else # we have an actual match, print it.
        value = P.traverse_match(p, mid, fold = fold_scheme)
        println("Parsed OK: $value")
        m = p.matches[mid] # skip the whole match and continue
        next_pos = nextind(p.input, m.last)
    end
end
