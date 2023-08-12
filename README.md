
# PikaParser.jl -- Parser library for Julia

| Build status | Documentation |
|:---:|:---:|
| ![CI status](https://github.com/LCSB-BioCore/PikaParser.jl/workflows/CI/badge.svg?branch=master) [![codecov](https://codecov.io/gh/LCSB-BioCore/PikaParser.jl/branch/master/graph/badge.svg?token=A2ui7exGIH)](https://codecov.io/gh/LCSB-BioCore/PikaParser.jl) | [![stable documentation](https://img.shields.io/badge/docs-stable-blue)](https://lcsb-biocore.github.io/PikaParser.jl/stable) [![dev documentation](https://img.shields.io/badge/docs-dev-cyan)](https://lcsb-biocore.github.io/PikaParser.jl/dev) |

A simple straightforward implementation of PikaParser in pure Julia, following
the specification by Luke A. D. Hutchison (see
https://github.com/lukehutch/pikaparser).

Pika parsers are pretty fast, they are easy to specify, carry the ability to
unambiguously match all PEG grammars including the left-recursive ones, and
provide great mechanisms for parsing error recovery.

## Example

```julia
import PikaParser as P
```

### Building a grammar

All grammar clauses are subtype of a `Clause`. The types are indexed by the
labels for your grammar rules -- Julia symbols are a natural choice, but you
are free to use integers, strings, or anything else.

```julia
rules = Dict(
    # match a sequence of characters that satisfies `isdigit`
    :digits => P.some(:digit => P.satisfy(isdigit)),

    # expression in parentheses
    :parens => P.seq(
        P.token('('),
        # you can name the rules in nested contexts
        :expr => P.first(:plusexpr, :minusexpr, :digits, :parens),
        P.token(')'),
    ),

    # some random operators
    :plusexpr => P.seq(:expr, P.token('+'), :expr),
    :minusexpr => P.seq(:expr, P.token('-'), :expr),
)

g = P.make_grammar(
    [:expr], # the top-level rule
    P.flatten(rules, Char), # process the rules into a single level and specialize them for crunching Chars
)
```

The grammar is now prepared for parsing.

### Parsing text

Parsing is executed simply by running your grammar on any indexable input using
`parse`.

(Notably, PikaParsers require frequent indexing of inputs, and incremental
parsing of streams is thus complicated. To improve the performance, it is also
advisable to lex your input into a vector of more complex tokens, using e.g.
`parse_lex`.)

```julia
input = "12-(34+567-8)"
p = P.parse(g, input)
```

You can find if an expression was matched at a certain position:
```julia
P.find_match_at!(p, :expr, 1)
```
...which returns an index in the match table (if found), such as `45`.

You can have a look at the match: `p.matches[45]` should return:
`PikaParser.Match(10, 1, 13, 2, 52, 0, 41, 0)`
where `10` is the renumbered rule ID for `:expr`, `1` is the starting position
of the match in the input, `13` is the last position of the match (here, that
means the whole input); `2` is the option index (in this case, it points to
`:expr` option 2, which is `:minusexpr`). The rest of the `Match` structure is
used for internal values that organize the match tree and submatches.

### Recovering parsed ASTs

You can use `traverse_match` to recursively walk the parse trees, to produce
ASTs, and translate, interpret or evaluate the expressions:
```julia
P.traverse_match(p, P.find_match_at!(p, :expr, 1))
```
By default, this runs through the whole match tree and transcodes the matches
to Julia `Expr` AST. In this case, if you pipe the output through
JuliaFormatter, you will get something like:
```julia
expr(
    minusexpr(
        expr(digits(digit("1"), digit("2"))),
        var"minusexpr-2"("-"),
        expr(
            parens(
                var"parens-1"("("),
                expr(
                    plusexpr(
                        expr(digits(digit("3"), digit("4"))),
                        var"plusexpr-2"("+"),
                        expr(
                            minusexpr(
                                expr(digits(digit("5"), digit("6"), digit("7"))),
                                var"minusexpr-2"("-"),
                                expr(digits(digit("8"))),
                            ),
                        ),
                    ),
                ),
                var"parens-3"(")"),
            ),
        ),
    ),
)
```

It is straightforward to specify your own method of evaluating the parses by
supplying the matchtree opening and folding functions. For example, you can
evaluate the expression as follows:
```julia
P.traverse_match(p, P.find_match_at!(p, :expr, 1),
    fold = (m, p, subvals) ->
        m.rule == :digits ? parse(Int, m.view) :
        m.rule == :expr ? subvals[1] :
        m.rule == :parens ? subvals[2] :
        m.rule == :plusexpr ? subvals[1] + subvals[3] :
        m.rule == :minusexpr ? subvals[1] - subvals[3] : nothing,
)
```

You should get the expectable result (`-581`).

#### Acknowledgements

`PikaParser.jl` was developed at the Luxembourg Centre for Systems
Biomedicine of the University of Luxembourg
([uni.lu/lcsb](https://www.uni.lu/lcsb)).
The development was supported by European Union's Horizon 2020 Programme under
PerMedCoE project ([permedcoe.eu](https://www.permedcoe.eu/)),
agreement no. 951773.

<img src="docs/src/assets/unilu.svg" alt="Uni.lu logo" height="64px">   <img src="docs/src/assets/lcsb.svg" alt="LCSB logo" height="64px">   <img src="docs/src/assets/permedcoe.svg" alt="PerMedCoE logo" height="64px">
