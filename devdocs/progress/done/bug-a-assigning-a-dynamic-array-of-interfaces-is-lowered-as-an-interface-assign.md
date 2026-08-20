---
track: A
prio: 70
type: bug
blocked-by: []
summary: "`b := a` on a dynamic array of interfaces was lowered as PXXIntfAssign over the array HANDLE — reading a dyn-array handle as an interface fat pointer and dispatching _Release through it. SIGSEGV, and it crashed even when every element was nil, because the elements were never involved. Integer, string and plain-record element types were unaffected."
status: done
owner: claude-acp
---

# Assigning a dynamic array of interfaces is lowered as an interface assign

- **Track A** (`compiler/ir.inc` assignment path; `compiler/symtab.inc` helper).
- Found 2026-08-20 by an FPC differential probe of interfaces held in containers.

## Measured

```pascal
var a, b: array of IFoo;
begin
  SetLength(a, 1);
  a[0] := TFoo.Create('z');
  writeln(a[0].Name);    { prints z }
  b := a;                { SIGSEGV }
```

| element type | `b := a` |
| --- | --- |
| `IFoo` | **SIGSEGV** |
| `IFoo`, every element still nil | **SIGSEGV** |
| `Integer` | fine |
| `string` | fine |
| plain record | fine |

Identical on pinned and on HEAD before the fix. FPC runs all of them.

## Cause

**An array's TypeKind IS its element kind.** So `b := a` arrives at the
assignment path with `lhsTk = tyRecord`, `ResolveNodeRec` answers `IFoo`, and the
COM-interface arm concluded the destination was an interface VALUE. It emitted

```
PXXIntfAssign(@b, @a, ifaceId)
```

which reads a dynamic-array handle as an interface fat pointer and dispatches
`_Release` through whatever the first word points at.

That the all-nil case crashed too is the tell: nothing about the elements is
involved — the ARRAY HANDLE itself is being treated as an object reference.

## Fix

`isComIntf` now also requires that the LHS is not a whole array, via a new
`ASTNodeIsWholeArray`. An array assignment is a whole-array copy and belongs to
the paths below, whatever its elements are.

Verified that the neighbouring shapes take the correct path: a static array of
interfaces copies by value, a record containing an interface array copies, and
`g.arr := h.arr` (a field that is a whole interface array) works.

## The pattern, fourth time today

This is the same mistake as `bug-a-a-local-array-of-interfaces-is-not-zero-initialised`
and `bug-a-a-record-with-an-interface-field-is-not-zero-initialised`, seen from
the other side. Those asked "is this refcounted?" of a CONTAINER and got False
when they needed True; this one asked it of an array and got True when it needed
False. **The container's shape and the member's kind are different questions, and
`TypeKind` cannot tell them apart because an array borrows its element's kind.**
Every pass that reads `TypeKind = tyRecord` on a possibly-array symbol is
suspect; the helpers accumulated today (`RecIsComInterface`,
`SymElemIsComInterface`, `ASTNodeIsWholeArray`) are the beginning of asking it
properly.

## Found in passing — NOT fixed here

Three more, each measured, each filed:

- `bug-a-setlength-shrink-does-not-release-dropped-interface-elements` — shrinking
  4→2 destroys 0 where FPC destroys 2.
- `bug-a-a-local-dynamic-array-of-interfaces-is-not-released-at-scope-exit` — a
  routine filling 2 elements and returning destroys 0.
- `bug-a-two-function-result-interfaces-into-a-local-dyn-array-segfault` — the
  sharpest of the three, and a crash.

## Test

`test/test_dynarray_of_interfaces_assign.pas` — 6/6, identical to FPC. The
assign, the all-nil assign, handle aliasing, static-array copy-by-value, a record
holding an interface array, and the integer/string element types that always
worked (so a fix cannot break them). **The pinned binary segfaults immediately.**

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.
