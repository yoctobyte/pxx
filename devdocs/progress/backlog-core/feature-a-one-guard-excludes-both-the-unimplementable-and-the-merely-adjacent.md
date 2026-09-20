---
slug: feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent
track: A
prio: 40
type: feature
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "builtinheap.pas gates whole REGIONS of the unit on a profile marker, so a routine is excluded from the bare ESP profile by where it sits in the file rather than by what it needs. Each {$ifndef PXX_ESP} / {$ifndef PXX_ESP_BARE} block contains a small genuine core -- a filesystem open, syscall stdio -- and a large remainder of pure pointer/memory code that would compile anywhere; ~25 routines (the managed record and dynarray retain/release walks, the variant runtime, PXXCStrToFrozen) are lost to bare for adjacency alone. The mechanism is a POSITIONAL guard standing in for a capability one, and it springs whenever a new routine is added inside an existing block: it inherits that block's exclusions silently and no diagnostic names the reason. The unit's own header already states the principle it violates -- none of these bodies is unimplementable on an ESP chip."
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
