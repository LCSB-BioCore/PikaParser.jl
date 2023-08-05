
# # Example: Parsing JSON

# Here we prepare a parser of a very small subset of JSON.
#
# The main features of the parser include:
# - handling sequences with separators
# - handling string escapes
# - building native Julia data objects using a dictionary of handlers
#
# The simplifications that we choose not to handle are the following:
# - we do not support space between tokens (you can pipe your json through
#   `jq -c .`
#   to remove unnecessary spaces)
# - support for numbers is very ad-hoc, `Float64`-only
# - the escape sequences allowed in strings are rather incomplete
#
# ## Preparing the grammar

import PikaParser as P

rules = Dict(
    :t => P.tokens("true"),
    :f => P.tokens("false"),
    :null => P.tokens("null"),
    :digit => P.satisfy(isdigit),
    :number => P.seq(
        P.first(P.token('-'), P.epsilon),
        P.some(:digit),
        P.first(P.seq(P.token('.'), P.many(:digit)), P.epsilon),
    ),
    :quote => P.token('"'),
    :esc => P.token('\\'),
    :string => P.seq(:quote, :instrings => P.many(:instring), :quote),
    :instring => P.first(
        :escaped => P.seq(:esc, P.first(:esc, :quote)),
        :notescaped => P.satisfy(x -> x != '"' && x != '\\'),
    ),
    :array => P.seq(P.token('['), P.first(:inarray, P.epsilon), P.token(']')),
    :sep => P.token(','),
    :inarray => P.tie(P.seq(P.seq(:json), P.many(:separray => P.seq(:sep, :json)))),
    :obj => P.seq(P.token('{'), P.first(:inobj, P.epsilon), P.token('}')),
    :pair => P.seq(:string, P.token(':'), :json),
    :inobj => P.tie(P.seq(P.seq(:pair), P.many(:sepobj => P.seq(:sep, :pair)))),
    :json => P.first(:obj, :array, :string, :number, :t, :f, :null),
);

# ## Making the "fold" function
#
# To manage the folding easily, we keep the fold functions in a data structure
# with the same order as `rules`:
folds = Dict(
    :t => (v, s) -> true,
    :f => (v, s) -> false,
    :null => (v, s) -> nothing,
    :number => (v, s) -> parse(Float64, v),
    :quote => (v, s) -> v[1],
    :esc => (v, s) -> v[1],
    :escaped => (v, s) -> s[2],
    :notescaped => (v, s) -> v[1],
    :string => (v, s) -> String(Char.(s[2])),
    :instrings => (v, s) -> s,
    :array => (v, s) -> s[2],
    :inarray => (v, s) -> s,
    :separray => (v, s) -> s[2],
    :obj => (v, s) -> Dict{String,Any}(isnothing(s[2]) ? [] : s[2]),
    :pair => (v, s) -> (s[1] => s[3]),
    :sepobj => (v, s) -> s[2],
    :inobj => (v, s) -> s,
);

default_fold(v, subvals) = isempty(subvals) ? nothing : subvals[1]

g = P.make_grammar([:json], P.flatten(rules, Char));

# ## Parsing JSON
#
# Let's parse a simple JSONish string that demonstrates most of the rules:
input = """{"something":123,"other":false,"refs":[1,-2.345,[],{},true,false,null,[1,2,3,"haha"],{"is\\"Finished\\"":true}]}""";

p = P.parse(g, input);

# From the result we can build a Julia JSON-like structure:
result = P.traverse_match(
    p,
    P.find_match_at!(p, :json, 1),
    fold = (m, p, s) -> get(folds, m.rule, default_fold)(m.view, s),
)

# Detail:
result["refs"]
