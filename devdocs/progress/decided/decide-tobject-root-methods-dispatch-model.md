---
track: U
prio: 65
status: decided
type: decide
---

# Decide: how `TObject.Equals` / `GetHashCode` dispatch — intercept, real parent, or reserved slots

- **Type:** decision (Track U) — blocks [[feature-pascal-builtin-tobject-class]],
  which blocks [[feature-pascal-corpus-generics]] (rung 3 of
  [[feature-pascal-corpus-oop]]).
- **Raised:** 2026-08-20 (frank1-ACP). **Answered:** 2026-08-21 by the user.

## ANSWER (user, 2026-08-21)

**Option C — reserved leading VMT slots, N = 4** (Destroy, Equals, GetHashCode,
ToString: FPC's set), **with a `--compact-classes` opt-out, which the ESP target
turns on by default and documents.**

> *"just memory is precious on that target."*

Implementation ticket: [[feature-a-tobject-root-method-vmt-slots]].

## Why C, measured rather than argued

The original write-up offered A/B/C and flagged C's key assumption as unchecked.
It was checked on 2026-08-21 (static reading of the compiler, not a build):

**The two walls decide it.** Both take their receiver as a **static `TObject`**
and need the dynamic class's override:

```pascal
class function TEquals.&class(constref ALeft, ARight: TObject): Boolean;
  ... Exit(ALeft.Equals(ARight))
class function THashFactory.&Class(constref AValue: TObject): UInt32;
  ... Result := AValue.GetHashCode;
```

That **kills option A** (parser intercept): non-virtual dispatch means every
comparer in `generics.defaults` that overrides `Equals` silently gets TObject's
identity comparison. Compiles clean, wrong answers.

It also kills a **fourth option found in the tree** and not in the original
write-up: `pasparser_decl.inc:4110` already solves this shape for
`Destroy`/`Create` by *materialising a root virtual on first override*.
Extending that name list looks like a one-liner, but it allocates a **different
slot number per hierarchy** and TObject still has none — so a static-`TObject`
call site has nothing to dispatch through. It works within a hierarchy; the
walls are outside one.

So a slot number fixed **at the root** is required: B or C.

**C's unmeasured assumption holds.** Nothing computes a slot number:

- all ~20 consumers (`pasparser_expr` / `_stmt` / `_lval`) read `UMthVirSlot[mmi]`
  back from the method record;
- VMT emission is generic — walk `0 .. UClsVirtCount[ci]-1`, resolve each via
  `ResolveVMTSlotProc`, fix up at `VMTOffset + i*8`;
- **no VMT slot literal exists anywhere in the compiler**;
- **the IMT is untouched** — a separate table indexed by declaration order
  *within an interface* (`_AddRef`/`_Release` at IMT 0..2), recovered per call
  from the instance's RTTI by interface id. A VMT base shift does not reach it.
  This was the write-up's named risk and it is clear.

## Cost, stated correctly

**Per class DECLARED, in the data section — not per instance, not per call.** An
object still carries one VMT pointer; a virtual call is still one indirect load.
10,000 instances of a class cost +32 bytes total, not +320 KB.

| class | today | N=4 | delta |
| --- | --- | --- | --- |
| no virtuals | 8 | 32 | +24 |
| overrides `Destroy` only | 8 | 32 | +24 |
| 3 virtuals + `Destroy` | 32 | 56 | +24 |
| 3 virtuals, no `Destroy` | 24 | 56 | +32 |

(Today's figures include Pascal's `if vmtSlots < 1 then vmtSlots := 1` floor.)
Roughly 6 KB of `.data` for a 200-class program.

## What `--compact-classes` does and does NOT cost

Under compact there is no root slot, so a static-`TObject` root-method call
**cannot be emitted and is a compile error naming the flag**. It cannot silently
do the wrong thing — the property that disqualified option A.

The blast radius is narrower than "no generics on ESP", which was an
overstatement made and withdrawn during this discussion:

- **Generics the language feature** (`TList<T>`, generic classes/functions, 17
  gated tests) — entirely unaffected.
- **`rtl-generics` the package** — mostly unaffected.
- **Only the default *class* comparer** (`TEquals.&class`,
  `THashFactory.&Class`) needs a root slot, i.e. a container keyed/compared on a
  **class reference** with no comparer supplied. `TList<Integer>`,
  `TDictionary<string, TFoo>`, record sorting: all fine.
- The escape is the library's own front door:
  `constructor Create(const AComparer: IComparer<T>)`.

## Recorded dissent, overruled — and correctly

The analysis argued against having the ESP target *imply* the flag, on the
grounds that a flag which silently changes what compiles is the opposite of the
predictability this repo asks for elsewhere. The user overruled it on the memory
budget, which is the call that is theirs to make. So: **ESP defaults to compact
and documents it**, and an ESP user who wants a class-keyed default comparer
turns the flag off in that build.

## Consequence to keep honest: the `Destroy` hack does not simply disappear

C was partly recommended because it lets `pasparser_decl.inc:4110`'s
`Destroy`/`Create` materialisation hack be **deleted** — a case removed rather
than added. With a compact mode that reverts to today's behaviour, the hack
survives as the compact-mode path unless compact reserves `Destroy` too. Left as
an implementation choice in the feature ticket, with a measurement to make; do
not let the write-up there claim a deletion that did not happen.

## The other finding: slot allocation is duplicated

`pasparser_decl.inc` (Pascal) and `pyparser.inc` (NilPy) each allocate slots and
each emit their own VMT, with `symtab.inc` zero-initialising at class mint. They
are the SAME class — one symbol table, one layout, and pyparser says so at the
site (*"same layout the Pascal path reserves… Keep the two in step"*) — but the
invariant is hand-maintained, and there is already one visible drift: Pascal
floors the VMT at one slot, NilPy does not. Benign today (no virtuals, no
dispatch), and pre-existing, not introduced by C. Filed as its own observation in
the feature ticket; C has to land in all three sites regardless.
