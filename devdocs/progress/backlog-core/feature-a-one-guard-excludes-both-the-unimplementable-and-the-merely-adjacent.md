---
slug: feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent
track: A
prio: 35
type: feature
status: working
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
