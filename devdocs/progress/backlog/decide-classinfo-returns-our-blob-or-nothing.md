---
track: U
prio: 35
type: decide
blocked-by: []
status: backlog
summary: "`TObject.ClassInfo` is the last unimplemented member of the TObject API. Returning our own class blob is right for identity comparison and wrong for anything that walks FPC's TTypeInfo layout. Three options: emit it as our blob, refuse it, or route it through the typinfo facade. Needs the owner's call on how far reflection parity goes."
---

# Decide: what `TObject.ClassInfo` returns

- **Type:** decision (Track U). Raised 2026-08-22 by claude-A while closing out
  [[feature-pascal-builtin-tobject-class]].
- Blocks the last row of
  [[feature-p-tobject-api-classparent-instancesize-tostring]] and the
  `tclassinfo1.pp` conformance skip (currently marked `wontfix`).

## The fork

`ClassInfo` is the only TObject member with no obvious answer.
`ClassParent`, `InstanceSize`, `ClassName`, `ToString`, `Equals` and
`GetHashCode` all work today and all have exactly one correct implementation.
`ClassInfo` has three, and they differ in what they PROMISE, not in cost:

**A — return our own class RTTI blob** (`UClsRTTIOff[ci]`, one pointer, ~free).
Correct for the common uses: identity (`A.ClassInfo = B.ClassInfo`), passing it
back into our own reflection, storing it as an opaque key. Wrong — silently, at
the caller's first field read — for any code that treats the result as an FPC
`PTypeInfo` and walks it, because our blob has a different layout. Same failure
mode this repo keeps paying for.

**B — refuse it** (`ClassInfo` stays a compile error naming the reason). Cannot
mislead. Costs nothing. Leaves `tclassinfo1.pp` skipped and any vendor unit that
merely MENTIONS `ClassInfo` uncompilable, even when it only compares pointers.

**C — return a `PTypeInfo` header from the typinfo facade.** The machinery
already exists: `TypeInfo(SomeClass)` mints a 24-byte
`{Kind; NamePtr; DataPtr}` header whose `DataPtr` points at that class's blob,
and `lib/rtl/typinfo.pas` declares the FPC-shaped API over it
(see [[feature-pascal-corpus-generics]], the 2026-08-01 entry). `ClassInfo`
becomes "the same thing `TypeInfo(TThatClass)` returns", which is what FPC
guarantees and what `tclassinfo1.pp` actually asserts
(`TObject.ClassInfo = TypeInfo(TObject)`). It is honest through the facade and
still not byte-compatible below it — but nothing real reads below the facade,
which is the settled position that unblocked the whole typinfo line.

## Recommendation

**C.** It costs one more `RegisterTypeInfoReq`-style request per class that uses
`ClassInfo` and makes the identity `o.ClassInfo = TypeInfo(TFoo)` true, which is
the property FPC code actually depends on and the one A quietly breaks. B is the
safe default only if the owner wants reflection parity to stop here.

The sub-question C raises, and the reason this is a decision rather than a task:
**per-class, or on demand?** `TypeInfo(T)` today is minted per distinct
compile-time USE. `ClassInfo` is a run-time member on a possibly-dynamic class,
so answering it for an arbitrary instance means every class carries a header —
another +8 bytes per declared class in `.data`, on top of the +8 `UnitName`
would want. That is the same budget conversation `--compact-classes` settled for
the VMT slots, and may want the same answer.
