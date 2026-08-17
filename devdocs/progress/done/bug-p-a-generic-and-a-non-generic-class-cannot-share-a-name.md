---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`THS = class ... end;` and `THS<T> = class ... end;` in one unit collide — pxx keys a class by NAME with no generic-arity component, so the second declaration overwrites the first and its methods report `unresolved forward`. FPC compiles the pair and prints both. Surfaces in rtl-generics as the misleading `base type not found: THS$LongInt`, because the collision is first observed through a base clause."
status: done
owner: claude-AP
---

# A generic and a non-generic class cannot share a name

Found 2026-08-16 walking rung 3 of the Pascal OOP corpus
([[feature-pascal-corpus-generics]]). It is the wall that stopped
`generics.defaults` after the four constant-initializer walls were cleared.

## Measured

```pascal
type
  THS      = class class function A: LongInt; static; end;
  THS<T>   = class class function B: LongInt; static; end;
```

| | result |
| --- | --- |
| FPC 3.2.2 `-Mdelphi` | `1 2` — both usable |
| pxx | `error: unresolved forward: THS.A` |

Narrowed against three controls, so the cause is the shared NAME and nothing
else:

| shape | pxx |
| --- | --- |
| generic, no constraint, plain base | **OK** |
| generic with a CONSTRAINED parameter (`<T: TCon>`) | **OK** |
| generic inheriting a DIFFERENTLY-named base | **OK** |
| generic + non-generic sharing a name, no inheritance at all | **FAILS** |

Constraints and generic inheritance both work. Only the name collision fails.

## Why the reported symptom is misleading

In rtl-generics the collision is first *observed* through a base clause —
`THashService<T: THashFactory> = class(THashService)` — and reports:

```
error: base type not found: THashService$TDelphiHashFactory
```

`$` is pxx's SPECIALIZATION mangling, not nesting. Read quickly, that message
says "a class nested inside a class is missing" and sends you at nested types;
this ticket was very nearly filed that way. What it actually says is that
resolving the base name `THashService` found the generic template being
specialized rather than the non-generic class, because there is only one entry
under that name. Inheritance is incidental — remove it and the pair still fails.

## Cause

A class is keyed by name alone; there is no generic-arity component to the key,
so `THS` and `THS<T>` are one row and the later declaration wins. The earlier
class's method bodies then have nothing to attach to, which is what surfaces as
`unresolved forward`.

This is the class/record name table, one of the six independent name tables
(`grep DeclVisible symtab.inc`) — so scope the fix to that table and check
whether the same key is built anywhere else before widening.

## Shape of the fix, and why it is not a microfix

The honest framing is **arity-overloaded class names**, not a special case for
this pair: FPC allows `TFoo`, `TFoo<T>` and `TFoo<T,U>` to coexist, and
`Generics.Collections` uses exactly that (`TDictionary` alongside
`TDictionary<K,V>`). A guard that merely tolerates one non-generic plus one
generic would clear this unit and break on the next.

That makes it a name-table key change plus every lookup that builds the key —
the sort of thing worth doing once, deliberately, rather than patched at the
site that happened to fail. Not started; no half-measure attempted.

## Blast radius to check before starting

Specialization is literal token-stream substitution (`SpecializeStream` in
parser.inc), so a specialized body referring to its own generic's bare name is
already textually rewritten before the parser sees it. Confirm what that does to
a base clause naming the non-generic sibling — it is the interaction most likely
to bite, and it is why the corpus failure appeared in a base clause first.

## Gate

The measured table above matching `fpc -Mdelphi` row for row, plus a
three-way (`TFoo`, `TFoo<T>`, `TFoo<T,U>`) coexistence case; `gate.sh quick`;
self-host fixedpoint.

## 2026-08-17 — FIXED in eda43dea7. The diagnosis above was wrong.

Both spellings now work; `TD`, `TD<K>` and `TD<K,V>` coexist and match
`fpc -Mdelphi` row for row.

**The name-table story in this ticket is wrong, and worth leaving on the record
rather than editing out.** It says a class is keyed by name with no arity
component, so the two declarations become one row. They do not: generic templates
live in `Templates[]` and classes in the `UCls*` table, and the two never
collided. I inferred a shared key from a single symptom
(`base type not found: THS$LongInt`) and then scoped a name-table redesign — "a
key change plus every lookup that builds the key" — around the inference.

**Two unrelated defects were wearing one symptom.**

1. `ParseSubroutine` handed a bare `X.M` implementation header to a TEMPLATE
   whenever a template of that name existed, matching on the name alone. That
   spelling is also how a generic method impl is legitimately written, so the
   header really is ambiguous and no spelling rule separates them; it is now
   resolved by asking which class DECLARES the method. This is what produced
   `unresolved forward` on the ordinary class's own method.

2. `SpecializeStream` rewrites every occurrence of the template's name to the
   specialized name, which also caught the base-class reference in
   `THS<T> = class(THS)` — emitting a specialization that inherits from itself.
   A base-class position now keeps the token, since the template's own name
   cannot mean the specialization there.

Neither is a name table.

**What separated them was two controls, in about a minute:** drop the
inheritance (defect 1 alone still fails), and drop each class's methods in turn
(only the ordinary class's method fails). Both were available yesterday when the
ticket was filed; I reasoned from the error text instead, which is the exact
failure this repo's debugging note warns about. The scope estimate was wrong in
the expensive direction — it made the work look like a design change worth
deferring, and it was two guards.

**Test.** `test/test_generic_name_overload.pas`, wired into `test-core`. The
inheritance row is the load-bearing one — `TD<LongInt>.N` must reach the
NON-generic parent's method through the specialization, which a compile-only
check would not catch. A typecast control (`TBox<T>(o)` inside a template body,
where the name DOES mean the specialization) guards the second fix from
over-reaching.

Unblocks [[feature-pascal-corpus-generics]]: generics.defaults walks from line
525 to 635, where the next wall is an inline `array[TTypeKind] of` type in a
class field — unrelated.

## Log
- 2026-08-17 — resolved, commit 604c26fda.
