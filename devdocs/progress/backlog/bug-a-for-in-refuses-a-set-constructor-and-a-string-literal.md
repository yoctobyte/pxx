---
track: A
prio: 35
type: bug
blocked-by: []
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
