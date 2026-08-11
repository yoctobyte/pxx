---
track: A
prio: 35
type: bug
blocked-by: []
status: done
owner: claude-A
---

# `for x in [...]` and `for c in 'literal'` are refused

- **Type:** bug (wrong refusal — valid FPC syntax) — **Track A**
  (Pascal frontend, but it lives in the shared `parser.inc`.)
- **Found:** 2026-08-10 by an FPC differential over the case/control-flow
  surface.
- **Pre-existing.**

```pascal
for i in [5, 1, 3, 2] do Write(i, ' ');   { FPC: 1 2 3 5 }
for c in 'hello' do Write(c, '.');        { FPC: h.e.l.l.o. }
```

pxx refuses the first with

    for-in: expected a generator, enum type, or iterable variable

and the second with a parse error at the literal. `for c in s` over a string
VARIABLE already works, which is the two-spellings tell again — the variable
form was implemented, the literal form never was.

## The trap: `[...]` here is a SET, not a list

**Do not implement this as list iteration.** Measured against `fpc -O1`:

| source | FPC output |
| --- | --- |
| `for i in [5,1,3,2]` | `1 2 3 5` — **ascending**, not source order |
| `for c in ['z','a','m']` | `a m z` — ditto |
| `for e in [eC,eA]` | `0 2` — ditto |
| `for i in [2..5]` | `2 3 4 5` — a range is a set range |
| `for i in [5,1,3,1,2]` | **compile error**: `duplicate set element` |

So the construct is "iterate the members of a set constructor in ordinal
order", with duplicates rejected at compile time — not "iterate these values in
the order written". Implementing the intuitive list semantics would produce a
silently different ORDER, which is exactly the class of bug that costs most here.

`for c in 'hello'` is separate and IS in source order: a string literal
iterates its characters, like the string-variable form that already works.

## Suggested scope

Two independent, small pieces; the literal-string one is the easy half and has
no semantic trap:

1. `for c in <string literal>` — route to the same lowering the string-variable
   form uses.
2. `for x in <set constructor>` — iterate set members ascending. The set literal
   is already built by the set machinery, so this is a bit-scan over it; reuse
   whatever `Include`/`in` uses rather than re-deriving. Reject duplicate
   elements to match FPC.

## Gate

The five rows in the table above matching FPC (including the duplicate-element
refusal), `for c in s` over a variable still green, self-host byte-identical.

## Resolution (2026-08-11)

Both halves, as the ticket scoped them, and the semantic trap it warned about
was honoured: **`[...]` is a SET, so iteration is in ORDINAL order**, verified
row by row against `fpc -O1` (`[5,1,3,2]` → `1 2 3 5`, `['z','a','m']` → `a m z`,
`[eC,eA]` → `0 2`, `[2..5]` → `2 3 4 5`, `[9,1..3,7]` → `1 2 3 7 9`, `[]` → no
iterations). A string literal is the opposite and iterates in SOURCE order, like
the string-variable form it now shares a lowering with.

Neither half needed new machinery. `BuildForInSetLoop` already scans a set by
membership; it only refused an ordinal-element set, so a bare `[5,1,3,2]`
constructor had nowhere to go — it now scans the set's 0..255 domain like the
`set of Char` arm beside it. The string literal materialises into a hidden
AnsiString local and drives the existing `ParseForInVarAST` loop, so it is
literally the same loop the variable form runs.

**Deliberate divergence from the ticket's gate — duplicates are ACCEPTED.** The
gate line asked for FPC's `duplicate set element` refusal. A set is idempotent,
so the restriction is historic rather than necessary, and CLAUDE.md is explicit
that the dialect stays lax by default with FPC-parity strictness behind a
per-feature `--strict-*` flag. `[5,1,3,1,2]` yields the same set, and the test
says so. Second, smaller divergence in the same direction: FPC refuses
`for c in 'x'` (a one-character literal IS a Char, and a Char has no
enumerator); pxx reads it as the one-character string it is written as.

New `test/test_forin_literal_sources.pas`, identical output on x86-64 and all
four cross targets; every row except the two documented divergences diffed
against `fpc -O1`.

## Log
- 2026-08-11 — resolved, commit 7ded8180a.
