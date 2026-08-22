---
slug: feature-a-tobject-instancesize-and-classnameis
track: A
prio: 35
status: done
commit: 5cdebf0f5
---

# TObject.InstanceSize and TObject.ClassNameIs

Two of FPC's System-level root class operations, reachable with no `uses`, were
missing:

```
pascal26: error: class method not found: InstanceSize
pascal26: error: "ClassNameIs": no such member on this record/class
```

Both now answer, on a class reference, an instance, a static `TObject` receiver
and a `TClass` variable alike, byte-identical to fpc 3.2.2.

## InstanceSize was pure omission

`rtti_emit.inc`'s pass 2 has **always** written the instance size into the class
blob:

```pascal
{ instance size }
PatchDataU64(hdr + 16, UClsSize_[ci]);
```

The value was there; only the accessor was missing. `__pxxInstanceSize` is one
field read, the same shape as `__pxxClassParent` two functions above it.

## ClassNameIs

A case-insensitive compare of the class's **own** name, which does *not* walk
the parent chain — `TDer.Create.ClassNameIs('TBase')` is False where
`InheritsFrom(TBase)` is True. Reuses `__pxxSameNameCI`, already in the same
unit, so the two cannot drift about what "same name" means.

## Where they plug in

Three sites, all existing:

1. `compiler/builtin/builtin.pas` — the two helpers, beside
   `__pxxClassName`/`__pxxClassParent`, plus a named `PXX_RTTI_INSTSIZE = 16`
   for the offset that was previously written by a bare literal on one side and
   never read on the other.
2. `pasparser_call.inc` — `GenMakeClassRefOp` gains two arms and
   `IsClassRefOpName` two names. `ClassNameIs` takes one argument, so it joins
   `InheritsFrom`'s existing argument arm rather than getting a second copy of
   it.
3. `pasparser_prog.inc` — the token pre-scan that decides whether to pull the
   builtin unit. Missing this is the failure mode where the feature works in a
   program that happens to `uses` something and not in one that does not.

## Verification

`test/test_tobject_instancesize_and_classnameis.pas`, wired into `test-core`,
byte-identical to fpc 3.2.2 (`cls 16 24` — the exact sizes agree, not just their
ordering). The rows that carry the weight:

- **`poly`** — a static `TObject` variable holding a `TDer` reports 24, not
  TObject's size. This is what proves the blob is reached *through the value* at
  run time rather than resolved from the declared type at compile time. A
  compile-time answer would have passed every other row.
- **`ref`** — the same through a `TClass` variable, the other runtime path.
- **`nis3`** — `ClassNameIs('TBase')` False and `InheritsFrom(TBase)` True on
  the same line, pinning that one walks the chain and the other does not.
- **`paren`** — FPC's empty-parens spelling on the no-argument form.

`make compiler/pascal26` fixedpoint converged in 1 round; `tools/gate.sh quick`
green.

**Pin note:** this touches `compiler/builtin/**`, which ships inside the binary,
so the pinned compiler does not have the helpers until the next pin. Nothing in
`lib/**` uses them, and the pinned compiler was re-checked against the modified
`builtin.pas` (additive only — it compiles and runs a class program unchanged),
so no pin is needed for this on its own.

## Found by

A 33-program class/property/interface differential — properties (field-backed,
getter/setter, read-only, indexed, default, inherited), virtual dispatch through
a base reference, abstract/override, class methods and class vars, virtual class
functions, `is`/`as`, `ClassName`/`ClassParent`/`InheritsFrom`, constructor and
destructor chains, `FreeAndNil`, nil `Free`, interfaces with refcounting and
`Supports`, method overloads, default parameters. **32 of 33 matched FPC
exactly**; this was the only gap.

## Still missing from the root set

Inventoried while here, in rough order of how likely real code is to want them:

| | notes |
| --- | --- |
| `UnitName` | needs the declaring unit's name in the blob, which is not there today |
| `ClassInfo` | the RTTI pointer in FPC's own format — a compat surface, not a field read |
| `FieldAddress` | needs published FIELD records; only published *methods* and properties are emitted |
| `NewInstance` / `FreeInstance` | the allocation hooks; meaningful only once a class can override them |
| `Dispatch` / `DefaultHandler` | the `message` handler mechanism, absent entirely |
| `CleanupInstance` / `InitInstance` | the managed-field walk, currently inlined at the ctor/dtor rather than exposed |
| `AfterConstruction` / `BeforeDestruction` | virtual hooks the ctor/dtor path does not call |
| class-side `MethodAddress` | works on an instance; the class-reference form does not |

None of them is a one-liner the way `InstanceSize` was, and none has a caller
yet. Filed here as an inventory rather than as eight tickets; promote
individually when something asks.
