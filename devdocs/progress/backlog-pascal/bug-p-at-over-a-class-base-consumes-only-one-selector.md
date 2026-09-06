---
slug: bug-p-at-over-a-class-base-consumes-only-one-selector
title: "`@` over a CLASS base consumes only one selector, so `@o.R.N` does not parse"
track: P
prio: 45
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-06 at d4fe6ede3, compiler e7d85ae887d9. `@o.R.N` where `o` is a CLASS instance is refused; fpc 3.2.2 -Mdelphi accepts it and prints TRUE. The boundary was varied and it is not about method pointers, indexed properties or events -- it is the CLASS BASE: `@r.Inner.N` (plain record, two dots) COMPILES, `@a[0].N` (array element then field) COMPILES, `@o.N` (class, ONE dot) COMPILES, and only `@o.R.N` (class, TWO dots) fails. LOCATED, and the code says it plainly: the `tkAt` arm at `compiler/pasparser_expr.inc:909` special-cases a class base, consumes the object name, the dot and exactly ONE identifier (method via FindUMeth, else field via FindUField), builds a single AN_FIELD over AN_ADDR and stops. There is no loop over further `.`/`[` selectors, so the rest of the designator is left in the token stream for the STATEMENT parser to choke on. ONE CAUSE, THREE FACES, which is why it reads as three unrelated bugs: `@o.R.Ev` gives `expected 'then' before '.'`, `@o.Sub.Items[0].Ev` gives the same, `@o.Items[0].Ev` gives `@obj.method: unknown method or field` (the identifier after the dot is a PROPERTY, so both FindUMeth and FindUField miss), and `p := @o.R.N` gives `a statement cannot start with '.'`. The error text depends on what follows the truncated parse, not on the defect. FOUND BY ATTEMPTING THE TARGET, and the edge runs OUTWARD from here: [[feature-embed-pascal-script]] carries `blocked-by` on this slug, uPSCompiler.pas:5031, `@Func.Attributes.Items[i].AType.OnApplyAttributeToProc`. NOT a blocker for the TMethod feature the arm exists for -- `@o.Ev` and `@o.Method` still work; this is the chain, not the base case."
---

# `@` over a class base consumes only one selector

- **Type:** bug (Pascal frontend — expression parsing)
- **Track:** P — `compiler/pasparser_expr.inc`, the `tkAt` arm
- **Found:** 2026-09-06, attempting [[feature-embed-pascal-script]], which is
  gated on this and carries the `blocked-by` edge (this ticket blocks it, not
  the other way round — PROSE EDGES BY DESIGN)

## Repro, and the boundary

`-Mdelphi`, at `d4fe6ede3` / compiler `e7d85ae887d9`:

| shape | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `@o.N` — class, one dot | compiles | compiles |
| `@r.Inner.N` — **record**, two dots | compiles | compiles |
| `@a[0].N` — array elem then field | compiles | compiles |
| **`@o.R.N` — class, two dots** | **`a statement cannot start with '.'`** | compiles, prints TRUE |

```pascal
type TInner = record N: Integer; end;
     TR = class public R: TInner; end;
var o: TR; p: Pointer;
begin o := TR.Create; p := @o.R.N; end.
```

## Why it reads as three bugs

The diagnostic is produced by whatever parses the *leftovers*, so it varies with
context while the defect does not:

| written | reported |
| --- | --- |
| `if @o.R.Ev <> nil then` | `expected 'then' before '.'` |
| `if @o.Sub.Items[0].Ev <> nil then` | `expected 'then' before '.'` |
| `if @o.Items[0].Ev <> nil then` | `@obj.method: unknown method or field` |
| `p := @o.R.N;` | `a statement cannot start with '.'` |

The third is the most misleading: the identifier after the dot is a **property**,
so `FindUMeth` and `FindUField` both miss and the arm reports a *lookup* failure
for what is really a *chaining* failure. Anyone landing on that message will go
looking for a missing property in the symbol table.

## The cause, from the code

`pasparser_expr.inc:909` — the arm exists to make `@obj.method` yield a TMethod
(Code+Data), which is a real and load-bearing feature. It handles exactly
`@ obj . ident`: consume the name, consume `.`, look the identifier up as a
method then as a field, build `AN_ADDR` over one `AN_FIELD`, `Next`, done. A
further `.` or `[` was never part of its grammar, and because the class case is
taken *instead of* the general designator path, it does not inherit the chaining
the record and array cases get for free.

## Suggested shape of the fix

Keep the TMethod special case for the exact `@obj.method` spelling it was written
for, and let anything that continues past one selector fall through to the
general designator parser with `AN_ADDR` applied to the result. **Check both
arms:** `pyparser.inc:43157` carries the identical error string and very likely
the identical structure.

## Done when

The four rows above all compile, `@o.Method` still yields a TMethod (assert it —
that is the feature this arm exists for, and it is what a naive "just use the
general path" fix would break), and uPSCompiler gets past line 5031.
