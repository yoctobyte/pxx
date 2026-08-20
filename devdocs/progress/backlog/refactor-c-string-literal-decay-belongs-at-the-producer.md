---
track: C
prio: 45
type: refactor
blocked-by: []
summary: "The +8 that turns a C string literal's handle into a char* is duplicated at three consumers (assign, return, call argument), each keyed on `ASTKind[...] = AN_STR_LIT`. Any wrapper node defeats all three at once -- which is exactly how bug-c-a-pointer-cast-of-a-string-literal-points-at-the-length-prefix happened. Do the decay once, at the producer."
status: backlog
---

# C string-literal decay belongs at the producer

Follow-up to `done/bug-c-a-pointer-cast-of-a-string-literal-points-at-the-length-prefix.md`,
which fixed the symptom by making a pointer cast of a literal an identity. The
underlying shape is still there.

## The shape

A string literal lowers to `IR_CONST_STR`, whose value is the frozen string's
**handle**: an 8-byte length prefix followed by the char data. C wants the data
pointer. So each consumer adds 8 for itself, in `compiler/ir.inc`:

| site | test |
| --- | --- |
| assignment | `CProgramMode and (ASTKind[ASTRight[node]] = AN_STR_LIT) and (lhsTk = tyPointer)` |
| `return` | the same on `ASTLeft[node]`, with a pointer return type |
| call argument | the same idea in the `tyString`->`tyPointer` marshalling |

Each carries its own comment pointing at the other two. Three copies of one
rule is what `devdocs/dev/root-cause-over-microfix.md` calls a design flaw
rather than a smell, and the failure mode is specific and nasty: the tests ask
about the node kind of *their own operand*, so **any** node in between defeats
all three at once. A cast did exactly that, and assignment, return and argument
passing all went wrong together — which made one shallow bug look like a deep
one.

Anything else that ever wraps a literal — a conditional operator yielding one,
a comma, a parenthesised compound expression, a future constant-folding node —
reintroduces the same bug in the same three places.

## What to do instead

In C mode a string literal has no other meaning: it IS a `char *`. So lower
`AN_STR_LIT` to `handle + 8` once, in the producer arm of `IRLowerAST` under
`CProgramMode`, and delete the three consumer skips. `sizeof "abc"` and the
array-ness of a literal are handled in the front end and do not read the IR
value, but check them; the indexing arm (`ir.inc` around the `AN_STR_LIT` base
case) computes its own base and must be re-pointed or left consistent.

## How to judge it

`--tier quick` is not the judge here. The C corpora — zlib, sqlite, quickjs,
tcc, lua — are what actually exercise every string path, and they run on Track
T. Land this behind a full corpus run, not a quick gate.
