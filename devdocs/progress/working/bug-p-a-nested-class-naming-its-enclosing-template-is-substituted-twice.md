---
slug: bug-p-a-nested-class-naming-its-enclosing-template-is-substituted-twice
track: P
prio: 70
type: bug
blocked-by: []
status: working
created: 2026-08-30
summary: "A nested class inside a generic template that names the ENCLOSING template as a type gets substituted twice -- the name to its specialized form AND the leftover `<T>` argument list separately -- so `FList: TCustomListWithPointers<T>` comes out as `TCustomListWithPointers$UInt32<UInt32>`. Wall at generics.collections.pas:214, reached once TArray is supplied."
owner: frankR
---

# P: a nested class naming its enclosing template is substituted twice

## Repro

`library_candidates/rtl-generics/.../generics.collections.pas:214`, reached with
`-dVER3_0_0` (which supplies the `TArray` the RTL is missing — see
[[bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2]]):

```pascal
  TCustomListWithPointers<T> = class(TCustomList<T>)
  public type
    TPointersEnumerator = class(TCustomPointersEnumerator<T, PT>)
    protected
      FList: TCustomListWithPointers<T>;     { <-- :214 }
      FIndex: SizeInt;
```

```
pascal26:214: error: unexpected token
  near: protected FList  TCustomListWithPointers$UInt32  UInt32 >>>  FIndex
```

## Diagnosis

Read the token stream in the `near:` line: `TCustomListWithPointers$UInt32`
followed by a **stray** `UInt32`. The field's declared type
`TCustomListWithPointers<T>` was rewritten twice —

1. the NAME `TCustomListWithPointers<T>` matched the enclosing template and was
   replaced by its specialized name `TCustomListWithPointers$UInt32`, and
2. the `<T>` argument list was *not consumed by that rewrite*, so the ordinary
   parameter substitution then turned its `T` into `UInt32` separately,

leaving `TCustomListWithPointers$UInt32<UInt32>` — a specialized name with an
argument list still attached, which is not a type.

Either rewrite alone is correct. The defect is that both run.

## Before closing: CHECK THE SIBLING

`devdocs/dev/normalise-dont-special-case.md` — if the enclosing template's name
is double-substituted through a nested CLASS field, look for the same shape
reachable another way before calling it fixed:

- a nested **record** naming the enclosing template;
- a nested **type alias** (`TSelf = TCustomListWithPointers<T>;`);
- a **method return type** or parameter naming the enclosing template;
- the enclosing template named in a nested class's **ancestor** clause;
- the same, one level deeper (nested inside nested).

Read each; do not assume the fix generalises and do not assume it does not.

## When it lands

Record where the wall moves to. A corpus that fails further on is progress worth
recording even when the next wall belongs to another lane.

Split out of [[bug-p-generic-type-param-unresolved-in-class-abstract-template]],
whose own premise is parked pending frank-user's shell history; this part is
independent of that question.
