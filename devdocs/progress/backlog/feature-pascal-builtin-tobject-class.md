---
track: P
prio: 42
type: feature
blocked-by: []
status: backlog
---

# Builtin TObject class — `var o: TObject` + `TObject.Create` + root methods

- **Type:** feature (Pascal frontend — builtin class) — **Track P/A**
- **Status:** unblocked 2026-08-22 (the decide is answered and implemented);
  only `UnitName` and `ClassInfo` remain — see the bottom of this file

## Symptom

`TObject` works as a PARAMETER type (tyPointer/elem tyClass, landed
bug-tobject-param-truncated-32bit) and as an implicit class PARENT
(`class(TObject)` — parent resolution special-cases it). But there is no real
TObject class ROW, so:

```pascal
var o: TObject;
begin
  o := TObject.Create;   { undefined variable (TObject) }
  writeln(o.GetHashCode);
end.
```

fails. Blocks tobject5, tclassinfo1 (also needs RTTI ClassInfo), and any
real-world code using a bare `TObject` instance (very common — Pascal Script,
Synapse hooks, LCL).

## Fix shape

Mirror RegisterBuiltinTGuid (a builtin record minted at ParseProgram start),
but as a CLASS: a zero-field TObject with a VMT, a `Create` constructor
(GetMem instance + stamp VMT + return), and `Free`/`Destroy` (the obj.Free
desugar already exists). FPC's TObject also has Equals/GetHashCode/ClassName/
UnitName/InstanceSize — add the simple ones (GetHashCode = PtrInt(self),
Equals = pointer compare); ClassName/UnitName/ClassInfo need RTTI (defer /
separate ticket).

The tricky part vs TGuid: a class needs a VMT slot table + a constructor
proc with a synthesized body. Look at how metaclass New / GenMakeFreeObject
build instances for the allocation shape.

## Slice 1 landed (2026-07-12, opus-p)

Instantiation works: `var o: TObject; o := TObject.Create; o.Free`, and a
child instance assigns to a TObject ref. RegisterBuiltinTObject mints the
root row (fieldless, VMT slot); the `class(TObject)` parent guard forces the
implicit-root model so no VMT relocates (an early real-parent version RED'd
test-core + cross ARC — fixed). Test: test_builtin_tobject.

**Remaining:** RTTI-backed root methods — GetHashCode (= PtrInt(self)),
Equals (pointer compare), ClassName / UnitName / InstanceSize / ClassInfo —
for tobject5/tclassinfo1. Needs the RTTI-on-IR surface; separate slice.

## Corpus evidence, and the fork (2026-08-20, frank1-ACP)

The "remaining" slice above is now the **only** thing between the rtl-generics
corpus rung and its next measurement, and it blocks it twice:
`generics.defaults.pas:1569` needs `TObject.Equals` and `:1780` needs
`TObject.GetHashCode`. Every default comparer in that unit overrides both. The
walls past them ([[feature-pascal-corpus-generics]], walls 28-33) could only be
measured by stubbing the two out in a throwaway copy of the tree.

That raises the slice's real value well above its `prio: 42`, but it is a
**decision, not a task**, and the ticket should not be picked up until it is
settled:

- **Parser intercept** (like `IsClassRefOpName`'s ops): cheap, no VMT change, and
  it unblocks the corpus today. But the methods are then not VIRTUAL — a
  descendant's `override` of `Equals` would not be dispatched through, which is
  precisely what generics.defaults does with them. So it unblocks compilation
  and may quietly produce wrong ANSWERS: the failure mode this repo keeps
  paying for.
- **Real virtual root slots**: correct, and what FPC has. Costs a VMT index
  shift for every class, which this ticket already records as having RED'd
  test-core + cross ARC once (see Slice 1) — the implicit-root guard exists to
  avoid exactly that.

The intercept is not a cheaper version of the slots; it is a different, weaker
guarantee, and the corpus is the caller that would notice. Recommend the slots,
scheduled deliberately rather than squeezed into a corpus session.

**2026-08-20, frank1-ACP:** that fork is now filed as
[[decide-tobject-root-methods-dispatch-model]] and this ticket is blocked on it.
Written as prose inside a feature ticket, the "do not pick this up until it is
settled" instruction was invisible to the ranker, which kept offering the ticket
as the top of Track A's queue. The decide ticket adds a third option the write-up
above did not consider (reserved leading VMT slots in every class, TObject still
implicit) and carries the recommendation.

## Gate

`make test` + self-host byte-identical; a compile-run test
(`var o: TObject; o := TObject.Create; o.Free`); unskip tobject5 (partial —
the RTTI-free assertions).

## 2026-08-22 — UNBLOCKED, and nearly done. Two members left.

The blocker [[decide-tobject-root-methods-dispatch-model]] was answered on
2026-08-21 (option C, reserved leading VMT slots, N = 4, with `--compact-classes`)
and its implementation ticket
[[feature-a-tobject-root-method-vmt-slots]] is in `done/`. Slot 0 (`Destroy`) was
the last unfilled one and landed in `24585b403`. So this ticket is no longer
blocked on anything.

Re-measured against a self-hosted binary at `0332839bc` — the six members the
ticket and [[feature-p-tobject-api-classparent-instancesize-tostring]] list, on a
`TD = class(TObject)` instance:

| member | today |
| --- | --- |
| `ClassParent` | works (non-nil for a class with a parent) |
| `InstanceSize` | works (12 for a one-Integer class) |
| `ClassName` | works |
| `ToString` | works — `'TD'`, and a descendant's `override` dispatches |
| `Equals` | works — including a descendant's `override` through a **static `TObject`** receiver |
| `GetHashCode` | works — same, virtual |
| `ClassInfo` | PXX-REJECT |
| `UnitName` | PXX-REJECT |

The virtual-dispatch check is the one that mattered: a `TFoo` overriding all
three, called through `function EqRoot(const L, R: TObject)`, agrees with
`fpc -Mobjfpc -O1 {$H+}` line for line. That is exactly the shape
`generics.defaults`' `TEquals.&class` / `THashFactory.&Class` use, so the corpus
walls at `generics.defaults.pas:1569` and `:1780` are cleared —
[[feature-pascal-corpus-generics]] is unblocked from here.

**Remaining, and neither is on the corpus path:**

- **`UnitName`.** Needs a unit-name word in the class RTTI blob. `RTTI_CLS_SIZE`
  is 96 and all twelve slots are taken (name, parent, instSize, vmt, propCount,
  props, methCount, meths, fieldCount, fields, ifaceCount, ifaces), so this is
  +8 bytes per declared class. The value is already tracked —
  `UClsUnitIdx[ci]` is the `Strs[]` index of the declaring unit, -1 for the main
  program — and nothing outside `rtti_emit.inc` depends on the blob's total size
  (`lib/rtl/rtti.pas` names field offsets, not a stride). The one wrinkle is that
  FPC answers `'System'` for `TObject` itself, which the builtin registration
  would have to say explicitly. Blocks the last assertion of `tobject5.pp`.
- **`ClassInfo`.** Deliberately last: returning our blob is honest for identity
  comparison and wrong for anything that walks FPC's `TTypeInfo` layout. That is a
  Track U call, not an implementation choice — see
  [[feature-p-tobject-api-classparent-instancesize-tostring]], which states the
  same trade-off.

Moved out of `blocked/`.
