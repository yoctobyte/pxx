---
track: A
prio: 40
type: feature
blocked-by: []
summary: "TObject.ClassParent was not implemented — `d.ClassParent.ClassName` failed with 'no such member on this record/class'. Its three siblings (ClassName, ClassType, InheritsFrom) already shared one resolver, so adding the fourth was one runtime helper plus three one-line entries, and it inherits the chaining, the four receiver kinds and the member-shadowing rule for free. Found by an OOP differential against FPC 3.2.2."
---

# `ClassParent` was missing from the class-reference operations

- **Type:** feature (missing `TObject` entry point) — Track A
  (`compiler/builtin/builtin.pas`, `pasparser_call.inc`, `pasparser_prog.inc`).
- **Status:** done
- **Opened:** 2026-08-21, from the OOP differential that also produced
  `bug-a-metaclass-create-needs-a-declared-constructor`.
- **Closed:** 2026-08-21.

## Symptom

```pascal
WriteLn(d.ClassName + '/' + d.ClassParent.ClassName);
```

```
pascal26:137: error: "ClassParent": no such member on this record/class
```

FPC has `ClassParent` on `TObject` and it is ordinary reflection code —
walking a hierarchy for a name, deciding how far down a class sits, printing an
ancestry chain.

## Why it was cheap

`ClassName`, `ClassType` and `InheritsFrom` are not three implementations; they
are one — `GenMakeClassRefOp` builds all three, `IsClassRefOpName` gates all
three, and `ParseClassRefOpTail` chains whichever of them yields a class
reference onto the next. That structure already carried every hard part:

- **four receiver kinds** — an instance, a `class of T` value, a `TClass`
  variable, and a static class name — because each of those call sites asks
  `IsClassRefOpName` rather than testing names itself;
- **chaining**, so `o.ClassParent.ClassParent.ClassName` works without anything
  new: `ClassParent` answers `tyPointer`, which is exactly the condition
  `ParseClassRefOpTail` loops on;
- **member shadowing** — a class that declares its own `ClassParent` member wins
  at the call site, since a real member outranks an operation in every arm.

So the whole feature is: one runtime helper reading one field, and three
one-line registrations. `__pxxInheritsFrom` already walks the very same
`+PXX_RTTI_PARENT` chain — `ClassParent` is one step of that walk.

This is what `normalise-dont-special-case.md` buys when it is followed: the
fourth case cost almost nothing *because* the first three were not three copies.
Contrast the metaclass-`Create` bug found in the same differential run, where
they were.

## Fix

1. `__pxxClassParent(Rtti: Pointer): Pointer` in `builtin.pas` — `nil` in, `nil`
   out; `nil` at the root, matching FPC's `TObject.ClassParent`.
2. A `ClassParent` arm in `GenMakeClassRefOp` with `outTk := tyPointer`.
3. `ClassParent` added to `IsClassRefOpName`.
4. The bare-name token pre-scan in `ParseProgram` pulls the builtin unit for it,
   beside `classname` / `inheritsfrom` — so it works with no `uses` clause, as
   a `System` entry point must.

## Verification

`test/test_classparent.pas`, wired into `test-core`, **byte-identical to fpc
3.2.2** across nine rows: two- and three-level chains, `= 'TObject'` at the top,
`TObject.ClassParent = nil`, the metaclass-value receiver, assignment into a
`TClass` and `InheritsFrom` off the result, the static class-name receiver, and
a class whose own `ClassParent` member shadows the operation.

Separately verified: a program with **no `uses` clause** compiles and runs it.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.
