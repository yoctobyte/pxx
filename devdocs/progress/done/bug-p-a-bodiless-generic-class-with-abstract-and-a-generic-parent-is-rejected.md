---
prio: 50
track: P
type: bug
status: done
blocked-by: []
found: 2026-08-30
found-by: frankA
summary: "ALREADY FIXED when re-measured 2026-09-04 at binary 62e6e63cd05b. `TD<T> = class abstract(TEnumBase<T>);` compiles, and so does this ticket's real-world motivator `TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);` and the `sealed` sibling. Fixed by the bodiless-modifier work recorded in test/test_generic_bodiless_class_modifier.pas, which lists this exact row. Closed on a measurement with a negative control, not on the test's existence."
---

# A bodiless generic class with `abstract` and a generic parent is rejected

## Repro

```pascal
unit u_c;
{$MODE DELPHI}
interface
type
  TBase = class
  end;
  TEnumBase<T> = class
  end;
  TD<T> = class abstract(TEnumBase<T>);     { <-- rejected }
implementation
end.
```

```
pascal26:11: error: unexpected token in a unit interface section:
             it starts no declaration (a mistyped section header?)
```

The error points at `end.` — the interface section was silently over-consumed,
so the reported line is nowhere near the cause.

## All three ingredients are required — measured

| shape | result |
| --- | --- |
| `TD<T> = class abstract(TEnumBase<T>);` | **FAIL** |
| `TD<T> = class(TEnumBase<T>);` (no `abstract`) | pass |
| `TD = class abstract(TBase);` (not generic, non-generic parent) | pass |
| `TD<T> = class(TBase);` (generic, non-generic parent) | pass |
| `TD<T> = class(TEnumBase<T>) end;` (with a body) | pass |

So it is not "bodiless classes", not "`abstract`", and not "generic parents" —
it is their intersection. **FPC compiles the failing row.**

## Why it matters

`rtl-generics` writes exactly this, and it is the first declaration of its kind
in `generics.collections`:

```pascal
TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);
```

It is on the path of [[feature-pascal-corpus-generics]] (rung 3).

## Relationship to the bound-name scan fix

Found while fixing a *different* defect in the same shape's neighbourhood —
`CollectNestedTypeNames` mis-tracked nesting depth on bodiless classes and
swallowed 11,312 tokens of `generics.collections`. That is fixed. This one is
the **parser** rejecting the declaration outright, which is a separate
mechanism and is why it is a separate ticket: the scan fix made the corpus
advance past it, and this repro isolates it standalone.

## Where to start

The class-header parse path, where `abstract`/`sealed` modifiers are consumed
relative to the parenthesised parent list — and specifically what happens when
the parent list contains a `<...>` group. The passing rows say each half is
handled; only the combination is not.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 71deb21d4.

## Closed 2026-09-04 (frankB) — measured fixed, with the instrument checked first

Re-measured at binary `62e6e63cd05b` while picking this rung up. All three rows
compile:

```pascal
TD<T>                      = class abstract(TEnumBase<T>);   { the ticket's repro }
TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);  { rtl-generics' own }
TSealedish<T>              = class sealed(TEnumerator<T>);
```

and `var d: TD<Integer>;` in the importing program binds, so the declaration is
not merely being skipped.

**The instrument was checked before the negative was believed.** A file that
compiles is exactly what a parser silently swallowing a declaration also
produces. Substituting `@@@` into the same slot of the same unit reproduces this
ticket's error verbatim — `pascal26:11: error: unexpected token in a unit
interface section: it starts no declaration (a mistyped section header?)` —
so the pass is a real negative and not a stray-token arm eating the row.

Fixed by the bodiless-modifier work in
`test/test_generic_bodiless_class_modifier.pas`, whose header lists
`TDerived<T> = class abstract(TBase<T>);  FAILS before / ok after` as one of its
measured rows. That test's existence is not what closes this; the measurement
above is. The test is why it stays closed.
