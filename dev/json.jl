
# # Example: Parsing JSON

# Here we prepare a parser of a very small subset of JSON.
#
# The main features of the parser include:
# - handling sequences with separators
# - handling string escapes
# - building native Julia data objects using a dictionary of handlers
#
# The simplifications that we choose not to handle are the following:
# - we do not support whitespace between tokens
# - for obvious reasons, we do not consider full floating point number support
# - the escape sequences allowed in strings are rather incomplete

import PikaParser as P

rules = Dict(
    :t => P.tokens(collect("true")),
    :f => P.tokens(collect("false")),
    :null => P.tokens(collect("null")),
    :int => P.some(:digit),
    :digit => P.satisfy(isdigit),
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
    :json => P.first(:obj, :array, :string, :int, :t, :f, :null),
);

# To manage the folding easily, we keep the fold functions in a data structure
# with the same order as `rules`:
folds = Dict(
    :t => (i, m, s) -> true,
    :f => (i, m, s) -> false,
    :null => (i, m, s) -> nothing,
    :int => (i, m, s) -> parse(Int, String(i[m.pos:m.pos+m.len-1])),
    :quote => (i, m, s) -> i[m.pos],
    :esc => (i, m, s) -> i[m.pos],
    :escaped => (i, m, s) -> s[2],
    :notescaped => (i, m, s) -> i[m.pos],
    :string => (i, m, s) -> String(Char.(s[2])),
    :instrings => (i, m, s) -> s,
    :array => (i, m, s) -> isnothing(s[2]) ? [] : s[2],
    :inarray => (i, m, s) -> s,
    :separray => (i, m, s) -> s[2],
    :obj => (i, m, s) -> isnothing(s[2]) ? Dict{String,Any}() : Dict{String,Any}(s[2]),
    :pair => (i, m, s) -> (s[1] => s[3]),
    :sepobj => (i, m, s) -> s[2],
    :inobj => (i, m, s) -> s,
)

default_fold(i, match, subvals) = isempty(subvals) ? nothing : subvals[1]

g = P.make_grammar([:json], P.flatten(rules));

# Let's parse a simple JSONish string that demonstrates most of the rules:
input = collect(
    """{"something":123,"other":false,"refs":[1,2,[],{},true,false,null,[1,2,3,"haha"],{"is\\"Finished\\"":true}]}""",
);

p = P.parse(g, input);

# Let's build a Julia JSON-like structure:
result = P.traverse_match(
    p,
    P.find_match_at!(p, :json, 1),
    fold = (r, m, s) -> get(folds, r, default_fold)(input, m, s),
)

# Detail:
result["refs"]
