---
slug: feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent
track: A
prio: 35
type: feature
status: backlog
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "builtinheap.pas gates whole REGIONS of the unit on a profile marker, so a routine is excluded from the bare ESP profile by where it sits in the file rather than by what it needs. Each {$ifndef PXX_ESP} / {$ifndef PXX_ESP_BARE} block contains a small genuine core -- a filesystem open, syscall stdio -- and a large remainder of pure pointer/memory code that would compile anywhere; ~25 routines (the managed record and dynarray retain/release walks, the variant runtime, PXXCStrToFrozen) are lost to bare for adjacency alone. The mechanism is a POSITIONAL guard standing in for a capability one, and it springs whenever a new routine is added inside an existing block: it inherits that block's exclusions silently and no diagnostic names the reason. The unit's own header already states the principle it violates -- none of these bodies is unimplementable on an ESP chip. PARTLY LANDED 2026-09-20: the record and dynarray walks and the class finalizer are no longer profile-gated; the arms inside them that touch a COM interface, a variant or a NilPy promo field still are, because those SURFACES are genuinely excluded on ESP while the walk that visits them is not. Managed records now compile AND RUN on bare metal -- test/test_esp_bare_managed.pas boots under qemu on esp32c3 and esp32s3 and matches its x86-64 oracle byte-for-byte. STILL POSITIONAL AND STILL TO DO: the variant runtime and the float-formatting routines, which share the 5649-6940 span with each other; the float half additionally needs the on-demand softfloat pull that bare deliberately skips, so it is not the same change."
---

## The shape

`builtinheap.pas:18` — `{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}` — makes
the bare profile inherit every `{$ifndef PXX_ESP}` region in the unit. Those
regions are contiguous spans of source, not capability sets:

| region | what genuinely cannot work on bare | what is excluded for adjacency |
| --- | --- | --- |
| `{$ifndef PXX_ESP}` 553-598 (decls), bodies at 3836, 4016, 4383, 5177, 5649 | `PXXStrLoadFile` — there is no filesystem under a bare boot | `PXXRecordRetain/Release/RetainIntf/ReleaseIntf/Initialize/Finalize/InitializeN/FinalizeN`, `PXXDynArrayRelease`, the `PXXVar*` family, `PXXIntfFromVariant`, `PXXPromoRetainOne`, `PXXWriteVariant`, `PxxSciDigits17` |
| `{$ifndef PXX_ESP_BARE}` 2944-3312 | console read/readln and the write helpers, which go through `PXXSysWrite` | `PXXCStrToFrozen` — a bounded copy into a length-prefixed buffer, no syscall in it |

## Why it is worth fixing on its own

It was found while chasing a bare **NilPy** profile, and that profile is
unbuyable for an unrelated reason
([[bug-a-the-bare-esp-profile-cannot-compile-any-nilpy-program]] — the runtime
does not fit in SRAM by ~1.9 MB). **This item does not depend on that.** A bare
**Pascal** program is a profile that already works and already fits, and it is
refused managed records, managed dynarrays and variants today purely by
position in a file.

## The one exclusion that is NOT positional

The float bodies genuinely need softfloat, and `PullSoftFloatBeforeBuiltinHeap`
(`frontend_prologue.inc`) skips bare deliberately so a float-free MCU program
does not pay ~54-64 KB of flash. Splitting the guards must not quietly pull
softfloat into every bare Pascal build — the float-formatting routines want a
guard of their own, keyed on whether the program uses floats at all, which is
the same on-demand scan the bare path already runs for a bare `sqrt(`.

## What would retire this

A bare Pascal fixture that declares a record with an `AnsiString` field, assigns
it, and lets it go out of scope — which needs `PXXRecordRelease` and therefore
cannot compile today. When that fixture passes, the positional guard is gone.
Note it must be a **new** fixture: `test-esp-bare`'s fourteen existing rows all
avoid managed members, which is why this has never shown up as a red.

## LANDED 2026-09-20 — the record half

**What moved.** Four spans in `builtinheap.pas` are no longer gated on the
profile marker: the `PXXRecordZeroManaged`/`Initialize`/`Finalize` family, the
`PXXClassFinalize` call arm, the big `PXXRecordRetain`/`Release` +
`PXXDynArrayReleaseDepth` span, and the span after it. What stayed gated is
narrower and now matches a capability rather than a position: the six
`PXXIntf*` arms, the five `PXXVar*` arms and one `PXXPromoRetainOne` arm inside
those walks, each a `kind = 4/5/7` case that cannot occur on a target where the
surface itself is excluded.

**The containment control, because this is RTL that every target links.** On a
non-ESP profile these spans were already fully included, so the change must be
a no-op there — and it is, byte-for-byte: a program exercising nested records,
a dynarray of strings, a variant, whole-record assignment and `Finalize`
compiles to an **identical binary** on x86-64 before and after, and still runs.
That control is not vacuous: the same edit moved three ESP fixtures from
`compiler error` to `ok`, so it demonstrably reaches output.

**The fixture asserts values, not compilation.** `test_esp_bare_managed.pas`
boots on bare `esp32c3` and `esp32s3` under qemu and prints
`local:in / copy:src:src / fin2:two / managed ok`, matching its x86-64 oracle.
A compile-only row could not tell a working walk from one that compiles and
then corrupts a refcount — which is the failure mode that matters here, since
the whole point of these routines is refcount bookkeeping.

**Softfloat is still on demand** — the float-free bare program is unchanged at
17,816 B against the float one's 59,944, so nothing here made bare pay for
formatting it does not use.

**The retirement test I first wrote was wrong and I ran it before trusting it.**
It said "a bare Pascal record with an `AnsiString` field going out of scope",
which **compiles fine** — a simple global record never reaches the walk. The
shapes that actually reach it are a record **local to a procedure**, a
**whole-record assignment**, and **`Finalize`**. Written from a prediction
about the mechanism rather than from the built thing; the fixture now contains
all three.

## THE VARIANT SPAN, MEASURED 2026-09-20 — NOT SPLIT, AND NOW A DECIDED QUESTION

The records half landed. The variant half was deliberately left, and this is
the measurement it was waiting on, taken at `85eef644b`.

The variant bodies live in **`builtinheap.pas:5701..6992`, one `{$ifndef
PXX_ESP}` span of 1292 lines**, and they share it with the entire float
FORMATTING family (`PXXWriteFloatNat/Fixed/Sci`, `PxxSci*`, `PxxIntDDigits`,
`PxxFracDigits`). That is the genuine dependency the ticket's parent already
names: `PullSoftFloatBeforeBuiltinHeap` skips bare on purpose so a float-free
MCU program does not pay ~54-64 KB.

**A per-routine census of the span, float-free versus float-coupled:**

| float-free | float-coupled, and it is REAL |
| --- | --- |
| `VarOpIsBitwise`, `VarBitwiseInt`, `PXXVarStrAppend`, `PXXVarClear`, `PXXVarReleasePayload`, `PXXPromoRetainOne`, `PXXVarRetain`, `PXXVarSetIntf`, `PXXIntfFromVariant` | `PXXVarBinOp` (`lDbl`/`rDbl`/`resDbl`, reads and writes `PDouble(v+8)^`), `PXXVarNot` (`Round(PDouble(...)^)`), `PXXWriteVariant` (calls `PXXWriteFloatNat`) |

**So the split is possible and it does not buy what it looks like it buys.**
Nine routines come free, but `PXXVarBinOp` is the core of variant arithmetic —
a bare Pascal program that uses an integer variant at all goes through it, and
its double arm is unconditional code, not a branch the linker can drop. **The
decision this reduces to is one sentence:** does a bare program that touches a
variant pay softfloat, or does `PXXVarBinOp`'s float arm get its own guard so
an integer/string variant is free? That is answerable with a size measurement
and does not need anyone's opinion — build the same program both ways.

**AND THE FIRST VERSION OF THAT TABLE WAS WRONG, IN THIS FILE'S OWN FAVOURITE
WAY.** A grep for `PXXWriteFloat|PxxSci|Double|...` scored `PXXIntfFromVariant`
at **four** float references, which would have put it on the coupled side. All
four are **two comment lines and two `forward;` declarations that belong to the
NEXT routine** — my routine-boundary scan attributed them upward. The routine
is float-free. *A search for a NAME matches PROSE ABOUT the thing as readily as
the thing*, and the count looked authoritative because it was per-routine and
tabulated. Read the lines, not the count: it took one command and moved a
routine across the table.

**What is NOT done here and is the next step:** the bare runtime ORACLE for
variants — a fixture in the shape of `test/test_esp_bare_managed.pas` that
asserts VALUES, so a split that compiles and then corrupts a payload is a diff
rather than a pass. Build it before touching the span, not after.

## THE SPAN IS THE SECOND WALL, NOT THE FIRST — MEASURED 2026-09-20, AND IT CORRECTS THE SECTION ABOVE

The census above framed this as "split the variant span". **That is not where a
bare Pascal variant program stops.** Written two hours earlier by me, from
reading the span rather than from running a program, which is the whole reason
the fixture exists.

`test/test_esp_bare_variant.pas` on `--esp-profile=bare --target=riscv32`
(identical on xtensa) refuses with:

```
pascal26:95: error: variant unbox: VariantToInt64 builtin not loaded
```

`VariantToInt64` is not in `builtinheap.pas` at all — it is in
`compiler/builtin/builtin.pas`, **which has ZERO ESP directives in it.** The
wall is `pasparser_prog.inc:1526`, where the builtin-unit pull is suppressed
for `TargetIsEspClass`, with the comment *"those targets cannot compile the
unit, and there a variant program fails at the call site instead."*

**THAT PREMISE IS A COMMENT, SO IT GOT MEASURED RATHER THAN OBEYED** — the
hazard-block rule. Three stubs, each one clearing the previous wall, restoring
the tree between:

| forced | next wall |
| --- | --- |
| `uses builtin` on bare | `StrFloat` → `PxxSciDigits17`, i.e. the excluded builtinheap span — **so the premise is TRUE, and the reason is float formatting, not anything about ESP** |
| + the span stubbed | `this target has no FPU and the soft-float kernel __pxx_l2d is not linked` |
| + `uses softfloat` in the program | **unchanged** — a program-level `uses` does not satisfy it, because the pull is ORDERED |

The last row lands on `frontend_prologue.inc:157`:

```pascal
if ((TargetArch = TARGET_RISCV32) or (TargetArch = TARGET_XTENSA)) and
   (not EspBareBoot) then
  ParseUsesUnitAmbient('softfloat');
```

`PullSoftFloatBeforeBuiltinHeap`, whose own comment states the policy: *"bare
stays on its own on-demand scan (no RTL, and ~54-64KB of flash a float-free MCU
program must not pay)."*

**SO THE CHAIN ENDS AT A DELIBERATE POLICY, NOT A DEFECT, AND THE TICKET
CHANGES SHAPE.** Variants on bare is not a guard-splitting job. It is:
`variant` → the builtin unit → float FORMATTING → softfloat → a named line that
deliberately skips bare. **Splitting `PXXVarBinOp`'s double arm, which the
section above proposed, would not have moved this at all** — the program never
reaches `PXXVarBinOp`; it stops one layer up, in a different file, at a
suppressed unit pull.

**The one-sentence question is therefore NOT the one written above.** It is:
**does a bare Pascal program that touches a variant pay the ~54-64 KB softfloat
cost, or does `builtin.pas`'s float-formatting surface (`StrFloat` and its
neighbours) get excluded so the rest of the unit is reachable without it?**

**FIRST-FAILURE CAVEAT, AND IT IS LOAD-BEARING HERE:** each row above is the
FIRST error after clearing the one before it. I stubbed rather than deepening a
census, per the rule, and a stub answers *"what is next"*, never *"what is
left"*. There may be further walls behind the softfloat one; nothing here says
there are not. What is established is that the first three are these three, in
this order, and that **none of them is the variant span the section above was
about.**
