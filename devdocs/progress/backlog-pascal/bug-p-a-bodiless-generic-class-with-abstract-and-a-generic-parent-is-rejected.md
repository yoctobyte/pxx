---
prio: 50
track: P
type: bug
status: backlog
blocked-by: []
found: 2026-08-30
found-by: frankA
summary: "`TD<T> = class abstract(TEnumBase<T>);` — a bodiless generic class with the `abstract` modifier and a generic parent — is rejected with `unexpected token in a unit interface section`. All three ingredients are required: dropping `abstract`, or making the parent non-generic, compiles. FPC compiles it. rtl-generics uses this exact shape."
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
