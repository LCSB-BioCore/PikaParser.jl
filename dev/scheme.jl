
# # Example: Parsing Scheme

# Here we prepare a small parser for a very simple Scheme-like language.
#
# The main features of the parser include:
# - handling whitespace
# - parsing number-containing identifiers and numbers while avoiding
#   ambiguities using `not_followed_by`
# - error recovery by manually traversing the memo table
#
# We choose not to implement any of the Scheme data types except numbers and
# identifiers; also all top-level expressions must be parenthesized "command"
# S-expressions.

import PikaParser as P

rules = Dict(
    :letter => P.satisfy(isletter),
    :digit => P.satisfy(isdigit),
    :ident => P.tie(
        P.seq(
            P.seq(:letter),
            P.many(:inIdent => P.first(:letter, :digit, P.token('-'))),
            P.not_followed_by(:inIdent),
        ),
    ),
    :number => P.seq(P.some(:digit), P.not_followed_by(:inIdent)),
    :ws => P.many(P.satisfy(isspace)),
    :popen => P.seq(P.token('('), :ws),
    :pclose => P.seq(P.token(')'), :ws),
    :sexpr => P.seq(:popen, :insexpr => P.many(:scheme), :pclose),
    :scheme => P.seq(:basic => P.first(:number, :ident, :sexpr), :ws),
    :top => P.seq(:ws, :sexpr), #support leading blanks
);

# Notice that the rules "clean" the space characters _after_ each sensible
# token is matched, except for `:top` that is able to clean up the leading
# spaces.  This way prevents unnecessary checking (and redundant matching) of
# the tokens, and buildup of uninteresting entries in the memo table.

# Let's test the grammar on a piece of source code that contains lots of
# whitespace and some errors.

p = P.parse(
    P.make_grammar([:top], P.flatten(rules, Char)),
    """
(plus 1 2 3)
(minus 1 2(plus 3 2)  ) woohoo extra parenthesis here )
(complex
  id3nt1f13r5)
(invalid 1d3n7)
(something
  1
  2
  valid)
(straight (out (missing(parenthesis error))
(apply (make-function) (make-data))
""",
);

# Prepare a folding function:

fold_scheme(m, p, s) =
    m.rule == :number ? parse(Int, m.view) :
    m.rule == :ident ? Symbol(m.view) :
    m.rule == :insexpr ? Expr(:call, :S, s...) :
    m.rule == :sexpr ? s[2] : m.rule == :top ? s[2] : length(s) > 0 ? s[1] : nothing;

# We can run through all `top` matches, tracking the position where we would
# expect the next match:

next_pos = 1
while next_pos <= lastindex(p.input)
    global next_pos
    pos = next_pos
    mid = 0
    while pos <= lastindex(p.input) # try to find a match
        mid = P.find_match_at!(p, :top, pos)
        mid != 0 && break
        pos += 1
    end
    pos > next_pos && # if we skipped something, report it
        @error "Got parsing problems" p.input[next_pos:prevind(p.input, pos)]
    mid == 0 && break # in case we have found a match, print its AST
    value = P.traverse_match(p, mid, fold = fold_scheme)
    @info "Got a command" value
    m = p.matches[mid] # skip the whole match and continue
    next_pos = m.pos + m.len
end

# We can see that the unparseable parts of input were correctly skipped, while
# the sensible parts were interpreted as expressions. The chosen error recovery
# method might not be optimal in the case of missing parentheses -- as an
# improvement, one might choose to utilize another grammar rule to find a good
# part of input to discard (e.g., everything to the end of the line).
