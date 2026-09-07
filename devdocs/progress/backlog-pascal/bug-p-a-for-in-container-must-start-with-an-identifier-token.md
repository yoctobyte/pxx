---
slug: bug-p-a-for-in-container-must-start-with-an-identifier-token
track: P
prio: 30
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-07
found-by: frankS
summary: "`for X in <container>` refuses before parsing anything unless the container's FIRST token is tkIdent -- so `for i in (v)`, `for i in 4` and `for i in Integer(4)` are rejected with `expected a generator, enum type, or iterable variable` while `for i in v` and `for i in Int64(4)` compile and match fpc. The discriminator is the TOKEN KIND, not the construct: Int64 lexes as tkIdent and Integer does not, so two spellings of the same cast get opposite answers. Loud, one line, and the general expression dispatch below it already handles every shape the gate excludes."
---

# A for-in container must start with an identifier token

`compiler/pasparser_stmt.inc:3087`:

```pascal
if CurTok.Kind <> tkIdent then
  Error('for-in: expected a generator, enum type, or iterable variable');
```

Measured 2026-09-07 at compiler `029799e446d5`, with
`operator enumerator(a: Int64): TEnum` in scope, against fpc 3.2.2:

| container | pxx | fpc |
| --- | --- | --- |
| `v` (Int64 variable) | 9 | 9 |
| `Int64(4)` | 4 | 4 |
| `Integer(4)` | **refused** | 4 |
| `4` | **refused** | 4 |
| `(v)` | **refused** | 9 |

**The tell is that `Int64(4)` works and `Integer(4)` does not.** Same construct,
same operator, same value — the only difference is that `Int64` reaches the
parser as `tkIdent` and `Integer` as its own token kind. Nothing about the
container's meaning is being consulted; the gate is reading the lexer.

## Why it is probably small

The gate guards a dispatch that already ends in a general container-EXPRESSION
path (dyn-array value, string value, set-valued call, and since 2026-09-07 any
value whose type has an `operator enumerator`). Every shape in the table above
is something that path can already decide — they are refused before reaching it,
not after failing in it. The `(v)` row is the clean demonstration: `v` alone
compiles, and one pair of parentheses is the entire difference.

## What to check before removing it

The gate predates the expression path and may be carrying a real
disambiguation — `for` has a counted form too, and `for i := 1 to 4` must not be
mistaken for a container. Establish what it was protecting before deleting it
rather than after: if the answer is "nothing any more", say so in the commit,
because a one-line deletion with no recorded reason is what makes the next
reader restore it.

Found while fixing
`test/test_for_in_operator_enumerator_on_an_alias_and_an_expression.pas`, whose
row 4 uses `Int64(4)` precisely because `Integer(4)` does not compile.
