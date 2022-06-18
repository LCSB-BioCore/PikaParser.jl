
# PikaParser.jl

A simple straightforward implementation of PikaParser in pure Julia, following
the specification by Luke A. D. Hutchinson (see
https://github.com/lukehutch/pikaparser).

Pika parsers are pretty fast, they are easy to specify, carry the ability to
unambigously match all PEG grammars including the left-recursive ones, and
provide great mechanisms for parsing error recovery.

## Example

```julia
using PikaParser
const P = PikaParser
```

### Building a grammar

All grammar clauses are subtype of a `Clause`. The types are indexed by the
labels for your grammar rules -- Julia symbols are a natural choice, but you
are free to use integers, strings, or anything else.

```julia
rules = Dict{Symbol,P.Clause{Symbol}}(
    # Terminal matches if the boolean function matches on input token.
    :plus => P.Terminal{Symbol}(==('+')),
    :minus => P.Terminal{Symbol}(==('-')),

    :digit => P.Terminal{Symbol}(isdigit),
    :digits => P.OneOrMore(:digit), # greedy repetition

    :plusexpr => P.Seq([:expr, :plus, :expr]), # sequence of matches
    :minusexpr => P.Seq([:expr, :minus, :expr]),

    :popen => P.Terminal{Symbol}(==('(')),
    :pclose => P.Terminal{Symbol}(==(')')),
    :parens => P.Seq([:popen, :expr, :pclose]),

    # the match is greedy -- take care about priority
    :expr => P.First([:plusexpr, :minusexpr, :digits, :parens, ]),
)

g = P.make_grammar(
    [:expr], # top-level rule
    rules,
)
```

### Parsing text

Pika parsers require frequent indexing of the input, Strings thus need to be
converted to character vectors to be usable as parser input. For performance,
it can be recommended to lex your input into a vector of more complex tokens.

```julia
input = collect("12-(34+567-8)")
p = P.parse(g, input)
```

You can find if something matched:
```julia
P.find_first_parse_at(g, p, 1)
```
...which should return `(1, :expr)`, telling that there's a match of `:expr` at
the first position.

You can also get the match index of the match, to find more about what was
matched:
```julia
P.find_match_at(g, p, :expr, 1)
```
...which returns an index in the match table (if found), such as `45`.

You can have a look at the match. `p.matches[45]` should return
```julia
PikaParser.Match(1, 13, 2, [44])
```
where `1` is the starting position in the input, `13` is the length of the
match (here, that is the whole input); `2` is the option index (in this case,
it points to `:expr` option 2, which is `:minusexpr`), and 44 is the submatch
of `:minusexpr`.

### Recovering parsed ASTs

You can use `traverse_match` to recursively walk the parse trees, to produce
ASTs, and translate, interpret or evaluate the expressions:
```julia
P.traverse_match(g, p, 45, :expr)
```
By default, this runs through the whole match tree and transcodes the matches
to Julia `Expr` AST. In this case, if you pipe the output through
JuliaFormatter, you will get something like:
```julia
:(expr(
    minusexpr(
        expr(digits(digit(), digit())),
        minus(),
        expr(
            parens(
                popen(),
                expr(
                    plusexpr(
                        expr(digits(digit(), digit())),
                        plus(),
                        expr(
                            minusexpr(
                                expr(digits(digit(), digit(), digit())),
                                minus(),
                                expr(digits(digit())),
                            ),
                        ),
                    ),
                ),
                pclose(),
            ),
        ),
    ),
))
```

It is straightforward to specify your own method of evaluating the parses by
supplying the matchtree opening and folding functions. For example, you can
evaluate the expression as follows:
```julia
P.traverse_match(g, p, P.find_match_at(g, p, :expr, 1), :expr,
    fold = (rule, match, subvals) ->
        rule == :digits ?
        parse(Int, String(input[match.pos:match.pos+match.len-1])) :
        rule == :expr ? subvals[1] :
        rule == :parens ? subvals[2] :
        rule == :plusexpr ? subvals[1] + subvals[3] :
        rule == :minusexpr ? subvals[1] - subvals[3] :
        nothing,
)
```

You should get the expectable result (`-581`).
