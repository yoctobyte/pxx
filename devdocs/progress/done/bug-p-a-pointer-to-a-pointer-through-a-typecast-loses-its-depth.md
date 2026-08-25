---
slug: bug-p-a-pointer-to-a-pointer-through-a-typecast-loses-its-depth
title: "`PPRec(pp)^^.f` resolves every field at offset 0, while `pp^^.f` is right"
track: P
prio: 50
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "The pointer-alias TYPECAST in ParseFactorCore runs its own suffix walk over `^`/`.`/`[]`, built on NodePtrElem — which answers only the IMMEDIATE pointee. So the deref nodes carried no remaining depth and no ultimate base record, ResolveNodeRec answered REC_NONE, and a trailing field landed at OFFSET 0. Silent wrong values; the same chain without the cast was correct. FIXED this session by pointing that walk at the shared ResolveDerefShape."
---

# Measured, 2026-08-25

```pascal
type
  TIn = record x, y: Integer; end;
  TOut = record a: Integer; inner: TIn; end;
  POut = ^TOut;  PPOut = ^POut;
var r: TOut; p: POut; pp: PPOut;
begin
  r.a := 1; r.inner.x := 5; r.inner.y := 9;
  p := @r; pp := @p;
  WriteLn(pp^^.inner.y);          { a }
  WriteLn(PPOut(pp)^^.inner.y);   { b }
  WriteLn(POut(p)^.inner.y);      { c }
end.
```

| | fpc 3.2.2 | pxx before |
| --- | --- | --- |
| a — no cast | 9 | 9 |
| b — cast + two derefs | 9 | **1** (= `r.a`) |
| c — cast + one deref | 9 | 9 |

Row b is the whole bug and it is the dangerous kind: it compiles, it runs, it
exits 0, and it answers the field at offset 0. A metaclass at the end of such a
chain went the same way — `PPVmt(pp)^^.ClassRef.Name` printed the class-ref
POINTER instead of calling the method, because `NodeMetaclassCi`'s FIELD arm
asks `ResolveNodeRec` too.

# Root cause — a FOURTH copy of the deref walk

`ParseLValueAST` has always resolved a `^` through `ResolveDerefShape`, which
returns the whole triple (remaining depth, ultimate base kind, ultimate base
record) and stamps it on the deref node. The pointer-alias cast arm in
`ParseFactorCore` (`compiler/pasparser_expr.inc`) had its own walk instead,
asking `NodePtrElem` — a function that by contract knows only the immediate
pointee and nothing about depth. One `^` was therefore fine and two were not.

Exactly the shape of the note already sitting in that arm
(`bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped`), one level
deeper: the same construct, two spellings, and the spelling with the cast is the
broken one. `devdocs/dev/normalise-dont-special-case.md` is the doctrine; this
was the fourth private notion of what a `^` yields.

# Fix (landed 2026-08-25)

The cast's suffix walk now calls `ResolveDerefShape` and stamps
`ASTSOffset`/`ASTSLen`/`ASTIVal` exactly as `ParseLValueAST` does. The adapter
casts (`ival` -1/-2, the PChar/`^Char` reinterprets) carry no alias row for the
resolver to read, so they keep the old alias-derived answer — detected by the
resolver yielding no shape at all rather than by a list of node kinds.

Regression test `test/test_pointer_to_a_pointer_through_a_cast_and_a_forward.pas`
(shared with [[bug-p-a-forward-declared-pointer-to-a-pointer-loses-a-level]]),
`.expected` from fpc 3.2.2.

# Where it was found

[[feature-pascal-corpus-generics]] — `PPExtendedEqualityComparerVMT(Self)^.__ClassRef`,
spliced into ~30 call sites of Generics.Defaults by a `{$DEFINE}`.

## Log
- 2026-08-25 — resolved, commit 15ec54d7a.
