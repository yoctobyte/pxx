---
track: U
prio: 55
type: decide
status: open
owner: ""
created: 2026-09-09
found-by: frankS
tags: [interfaces, abi, representation]
blocked-by: []
summary: "The fork inside bug-a-a-hand-built-com-interface-cannot-be-called, lifted out because it was ranked 55 under a live umbrella with the architecture decision buried in a bug body -- every `ready --track A` surfaced it to a seat that had to make an ABI call alone or skip, and skipping leaves no trace. THE PREMISE IS NOT IN DOUBT and this is not a compat-or-not question: FPC accepts, and its own packages rely on, a construct we cannot run (rtl-generics reaches every default comparer through a hand-built {VMT, RefCount, Size} record used as an interface), which is `compat, ranked by how much real code uses it` -- and it blocks feature-pascal-corpus-generics. The MIRROR (`IFoo(Pointer(anObject))` works here, RTE 216 under fpc) is the other direction and `us accepting what FPC rejects is not a defect` disposes of it; the two rules do not collide, they describe the two directions. What is genuinely open is HOW: (A) a synthesised RTTI shim at a cast whose operand is statically a non-class pointer, or (B) move pxx to FPC's representation, where the interface value IS the IMT pointer. Recommendation: A, because the one-word value is load-bearing in at least four places that would all move under B. Neither is attempted."
---

# How does a hand-built COM interface become callable?

The measurement, the repro and the mirror control live in
[[bug-a-a-hand-built-com-interface-cannot-be-called]] and are not repeated here.
One sentence of it: **pxx's interface value is the INSTANCE, with the IMT
recovered per call from the instance's RTTI blob; FPC's value IS the IMT
pointer.** The IMT *contents* already agree.

## Not the fork

Whether this is a defect at all. It is. FPC accepts — and FPC's own packages
depend on — a construct we cannot run, which is `compat, ranked by how much real
code uses it`, and the real code blocks an umbrella. The mirror control is the
OTHER direction and is disposed of by `us accepting what FPC rejects is not a
defect`. Recorded because the mirror reads like a reason to close this, and it
is not one.

## Option A — a synthesised shim at the cast (recommended)

A hard cast to an interface type whose operand is **statically** a non-class
pointer is precisely the hand-built case, and the cast site knows it. Emit a
shim object carrying real pxx RTTI whose interface table maps the target id to
the raw pointer, so `PXXIntfIMTOf` finds it by the existing walk.

- **For:** local. Nothing else in the compiler or RTL moves. The one-word value
  keeps its meaning everywhere, including the four places that read it as an
  instance: `AN_INTF_CALL`'s lowering, the ARC assign/release helpers,
  `PXXIntfComIMTOf`'s variant path, and the emitted nil checks.
- **Against, and this is the real cost:** the shim needs storage and a lifetime.
  Static-per-cast-site is wrong if the same site casts different pointers;
  heap-per-cast needs a free, and the thing being cast is by construction an
  object whose refcounting we do not control.
- **Open sub-question, cheap to measure:** how many distinct cast sites does
  `generics.defaults.pas` actually reach? If the answer is "one, in
  `_LookupVtableInfoEx`", the storage question shrinks to almost nothing.

## Option B — adopt FPC's representation

Make the interface value the IMT pointer.

- **For:** ABI-compatible with FPC and Delphi, so hand-built tables, foreign
  objects and anything else written to the documented layout work with no
  special case. Removes `PXXIntfIMTOf` from every interface call — a runtime
  walk per call, which is also a cost we currently pay.
- **Against:** the value stops identifying the instance, and four mechanisms
  named above read it as one. `PXXIntfComIMTOf` exists specifically because a
  variant slot holds only the instance; that whole design inverts. This is a
  cross-cutting ABI change and every pin between the change and the next one is
  incoherent for interfaces.

## What would settle it

Not a discussion — two measurements. **(1)** the cast-site count above, which
prices A. **(2)** how many places actually read an interface value as an
instance: I named four from reading, and that number is the price of B and I
have not counted it. Whoever takes this should get (2) before arguing either
way; my recommendation of A is made without it and should not outrank it.
