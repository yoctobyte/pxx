---
track: U
prio: 35
type: decide
blocked-by: []
status: decided
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

---

# DECIDED 2026-08-25 — **option C: `ClassInfo` returns the typinfo-facade `PTypeInfo`**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived.**

`x.ClassInfo` returns exactly what `TypeInfo(TThatClass)` returns: the 24-byte
`{Kind; NamePtr; DataPtr}` header, `DataPtr` pointing at that class's blob. The
identity `o.ClassInfo = TypeInfo(TFoo)` is true, which is the property FPC code
actually depends on and the one that `tclassinfo1.pp` asserts.

This is the same decision as
[[decide-tobject-classinfo-blob-or-refusal]], which asked the same question with
a different option lettering. Both are answered here; neither is a separate call.

## Why not A (our raw blob)

`frontend-compat-philosophy.md`, and it is not a close reading:

> *"a **silent wrong VALUE** is a bug in any dialect. Being our own dialect
> licenses different SEMANTICS chosen on purpose; it never licenses a wrong
> answer nobody chose."*

A layout walker reading `PTypeInfo(x.ClassInfo)^.Kind` off our blob reads an
interned-name pointer's low byte as a `TTypeKind`. That is garbage that looks
like an answer, with no diagnostic — the exact failure this rule names. A is
forbidden by a stated principle, not merely disfavoured.

## Why not B (keep refusing)

Refusing is defensible only while there is no correct answer available. There
is one, it costs one word per class, and the precedent for reaching it is
already settled: the typinfo facade is what unblocked the whole RTTI line, on
the finding that *"nothing real reads below the facade"*. Refusing now would be
choosing a loud gap over an available correct answer — and it blocks any vendor
unit that merely mentions `ClassInfo` while comparing pointers, which is the
common case, against the pragmatic goal of compiling real code.

## The sub-question the ticket flagged: per-class, or on demand?

**Per declared class.** `ClassInfo` is a runtime member on a possibly-dynamic
receiver, so "on demand" cannot be answered statically — the only way to answer
it for an arbitrary instance is for every class to carry a header.

Cost is one word in `.data` per declared class, and `UnitName` just demonstrated
that this header grows freely: nothing strides over these headers and every
reader names a field offset. This is **not** the `--compact-classes` budget
conversation, which was about per-class VMT *slots* multiplied by method count;
this is one word, once, per class.

## The line this shares with two sibling decisions

The facade speaks FPC's numbering; our internal blob stays private. Same seam
as [[decide-rtti-kind-numbering]] and
[[decide-vartype-returns-pxx-tags-not-fpc-codes]] — three tickets, one policy,
now written down in `README-agent-decisions.md`.

## Re-filed as work

Track **A**: `feature-a-classinfo-returns-the-typinfo-header`, prio 45 — mint a
`TYPEINFO_REQ_CAT_CLASS` header per declared class, add the `ClassInfo` accessor
arm, and unskip `tclassinfo1.pp`. Unblocks the ClassInfo rows of
[[feature-pascal-builtin-tobject-class]] and
[[feature-p-tobject-api-classparent-instancesize-tostring]].

## Log
- 2026-08-25 — decided, commit 28c19f214.
