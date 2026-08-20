---
track: A
prio: 70
type: bug
blocked-by: []
summary: "No class inherited from TObject at run time: a root class's RTTI blob carried a nil parent, so `b is TObject` and `TBase.InheritsFrom(TObject)` answered FALSE for every class in the program, and `except on E: TObject` never fired -- a catch-all handler let the process abort with an unhandled exception instead of catching."
status: done
owner: frank1-ACP
---

# A class does not inherit from TObject at run time

- **Track A** (`compiler/rtti_emit.inc` — the class RTTI blob), surfaced through
  the **Track P** Pascal surface (`is`, `InheritsFrom`, `except on`).
- Found 2026-08-20 by an FPC differential probe over the TObject API.

## The measurement

`fpc -O- -Mobjfpc` 3.2.2 vs pxx at `9c309d057`. Every row is a silent wrong
value — nothing warned, nothing crashed at the point of the defect.

| expression | FPC | pxx | 
| --- | --- | --- |
| `TBase.InheritsFrom(TObject)` | TRUE | **FALSE** |
| `TDer.InheritsFrom(TObject)` | TRUE | **FALSE** |
| `b is TObject` | TRUE | **FALSE** |
| `b.InheritsFrom(TObject)` | TRUE | **FALSE** |
| `TExplicit.InheritsFrom(TObject)` (declared `class(TObject)`) | TRUE | **FALSE** |
| `TDer.InheritsFrom(TBase)` | TRUE | TRUE |

That last row is what hid this for so long. Every link a program *writes down*
worked; only the link nobody writes — the implicit root — was missing. So a
class hierarchy behaved correctly right up to the moment something reached the
top of it.

And the expensive symptom, which is not a wrong boolean but a **lost program**:

```pascal
try
  raise Exception.Create('z');
except
  on E: TObject do writeln('caught ', E.ClassName);
end;
```

FPC catches. pxx printed `Unhandled exception: Exception: z` and aborted — the
catch-all handler was skipped, because handler matching is the same
`__pxxInheritsFrom` walk. A program whose top-level guard is `on E: TObject`
had no guard at all.

## Root cause

`RegisterBuiltinTObject` (`parser.inc:36075`) deliberately keeps TObject an
**implicit** parent: a class declared `class ... end`, and equally one declared
`class(TObject) end`, is registered with `parentCi = -1`. That is correct and
must stay — it is what stops a VMT from relocating for a parent that contributes
no fields and no virtual methods.

But `rtti_emit.inc` wrote the blob's parent word only when `UClsParent[ci] >= 0`:

```pascal
if (UClsParent[ci] >= 0) and (UClsRTTIOff[UClsParent[ci]] >= 0) then
  AddDataPtrFix(hdr + 8, UClsRTTIOff[UClsParent[ci]]);
```

so a root class's `PXX_RTTI_PARENT` stayed nil, and the runtime walk in
`__pxxInheritsFrom` (`builtin.pas`) terminated one link before TObject.

The two facts were each locally right and jointly wrong: **layout** parentage
(`parentCi`) and **identity** parentage (the RTTI chain) are different questions,
and one field was answering both. The fix separates them — the blob links to
TObject's RTTI even when the class has no layout parent:

```pascal
else if (UClsParent[ci] < 0) and (not UClsIsInterface[ci]) then
begin
  tobjCi := FindUClass('TObject');
  if (tobjCi >= 0) and (tobjCi <> ci) and (UClsRTTIOff[tobjCi] >= 0) then
    AddDataPtrFix(hdr + 8, UClsRTTIOff[tobjCi]);
end;
```

The `tobjCi <> ci` guard keeps TObject itself from pointing at itself (an
infinite walk), and the interface guard keeps an interface out of the class
chain — an interface is not a TObject and `IFoo.InheritsFrom(TObject)` must
stay false. Emission is already two-pass (all blobs allocated, then headers
filled), so TObject's offset is known when any class's header is written,
whatever the declaration order.

## Test

`test/test_class_inherits_from_tobject.pas`, 24 rows, all FPC-verified. It
covers the implicit root, the explicit `class(TObject)` spelling, a two-deep
chain, the reflexive `TObject.InheritsFrom(TObject)`, the negatives that must
stay false (`TRoot.InheritsFrom(TDer)`, `r is TDer`), a TObject-typed variable
reporting its real class, `on E: TObject` catching, a specific handler still
winning over it, and an interface implementor. Pinned scores two `is TObject`
failures and then **aborts** on the unhandled exception; the fixed compiler
matches FPC 24/24.

## Still open — the TObject API surface

The same probe found six TObject members pxx REJECTS outright and FPC accepts:
`ClassParent`, `InstanceSize`, `ClassInfo`, `ToString`, `Equals`,
`GetHashCode`. Those are loud (a compile error, not a wrong value), so they are
filed separately: `feature-p-tobject-api-classparent-instancesize-tostring`.

## Gate

`make compiler/pascal26` fixedpoint converged after 2 rounds; `tools/gate.sh
quick` GREEN.
