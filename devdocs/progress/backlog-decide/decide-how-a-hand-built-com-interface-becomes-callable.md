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

## Both measurements, taken 2026-09-09 (frankH) — and they move the fork

Taken because the ticket asks for them before either option is argued. Neither
option is chosen here; what follows prices them.

### (1) The cast sites in `generics.defaults.pas`: there are NONE

`/home/neo/src/fpc-trunk/packages/rtl-generics/src/generics.defaults.pas`
contains **zero** written casts of a pointer to an interface type. The
conversion is an IMPLICIT ASSIGNMENT: `_LookupVtableInfo` and
`_LookupVtableInfoEx` are declared `: Pointer`, and six sites assign their
result straight into an interface-typed `Result` —

    1108  Result := _LookupVtableInfo(giComparer, ...)            IComparer<T>
    2756  Result := _LookupVtableInfo(giEqualityComparer, ...)    IEqualityComparer<T>
    2764  Result := _LookupVtableInfoEx(giExtendedEquality..., ...)
    2766  Result := _LookupVtableInfoEx(giEqualityComparer, ...)
    2908  Result := _LookupVtableInfo(giExtendedEquality..., ...)
    2918  Result := _LookupVtableInfoEx(giExtendedEquality..., ...)

(`:3502` is the seventh occurrence and is Pointer-to-Pointer, not a conversion.)

**So option A as written does not fire on the code that motivates it.** Its
trigger is *"a hard cast to an interface type whose operand is statically a
non-class pointer"*, and the real source never writes one. The discrimination
point exists and is still compile-time visible — a `Pointer`-typed value
reaching an interface-typed destination — but it is an ASSIGNMENT rule, not a
cast rule, and an implementation keyed on the cast would compile
`generics.defaults` and change nothing. **This is the ticket's own hazard from
the other side: the shape a fix keys on has to be the shape the source
actually writes.**

**It also answers the storage sub-question, differently and better than "one
site" would have.** The operands are not dynamic: the hand-built instances are
TYPED CONSTANTS, one per element type —

    Comparer_Int32_Instance : Pointer = @Comparer_Int32_VMT;

— fourteen of them plus the ShortString family. So a shim can be keyed on the
OPERAND (static, one shim per hand-built table, materialised beside it) rather
than on the site, and both objections in A's "against" evaporate: no
same-site-different-pointer problem, and no lifetime problem, because a shim
for a static operand is itself static. The two dynamic comparers
(`Comparer_Binary`, `Comparer_DynArray` — commented out in the const block as
*"dynamic instance"*) are the exception and would need the heap answer, so the
count that matters is "how many operands are NOT static", not "how many sites".

### (2) The places that read an interface value as an instance: not four, and the four is the wrong axis

**The dereference `[inst]` -> vmt -> `[vmt-8]` -> rtti exists in exactly TWO
functions in the whole tree**, both in `compiler/builtin/builtinheap.pas`:
`PXXIntfIMTOf` (`:3602`) and `PXXIntfComIMTOf` (`:3628`). Every other name in
the family — `PXXIntfAddRef`, `PXXIntfRelease`, `PXXIntfAddRefAny`,
`PXXIntfReleaseAny`, `PXXIntfAddRefRaw`, `PXXIntfAssign`,
`PXXIntfFromVariant` — routes through one of those two and never touches the
layout itself. So two of the named four (the ARC helpers, the variant path)
are not independent sites; they are callers of the two that are.

**One of the four is representation-agnostic and should come off the list.**
The emitted nil check (`IRWrapNilChk`, `ir.inc:16556`) compares the word to
nil. An IMT pointer is nil-checkable exactly as an instance pointer is; that
site does not care what the word means.

**And the one that decides B is not on the list at all: `Self`.**
`AN_INTF_CALL`'s lowering (`ir.inc:16542`) takes the callee's `Self` from the
interface value itself — `Self = [iface]` — and then calls
`PXXIntfIMTOf(self, ci)` for the code address. Under B the value is the IMT,
and **pxx's IMT is a bare array of code addresses**: no offset-to-object field,
no adjustor thunks. There is nowhere for `Self` to come from. B therefore is
not "four read sites move"; it is *every interface method call's receiver*
plus a change to how IMTs are BUILT (`rtti_emit.inc`) to carry what FPC's
carry.

**So the answer to "is four the number or the first four" is neither.** Two of
it collapses into one pair of functions, one of it is not a read of the
meaning, and the item that prices B was absent. The recommendation of A was
correctly flagged as made without this measurement; with it, B is *more*
expensive than the recommendation assumed and A is *cheaper* — but A must be
re-specified onto the assignment, because the cast it keys on does not occur.

**Still not decided here, and deliberately.** What (1) and (2) settle is the
price. What they do not settle is whether pxx wants FPC's interface ABI as a
GOAL — `the-goal-cross-cross` wants foreign objects and documented layouts to
work, and that is an argument for B that no cost measurement can answer.
