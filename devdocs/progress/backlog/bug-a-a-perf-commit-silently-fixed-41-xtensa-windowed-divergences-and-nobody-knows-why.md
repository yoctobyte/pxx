---
slug: bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why
track: A+S
prio: 45
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
owner: unassigned
summary: "75d2ba662 pads Code[] so data starts on its own page — filed and reviewed as a qemu PERFORMANCE fix (287x). Bisected: it also takes xtensa/windowed from 53 to 94 of 129 programs matching the oracle, lost=0 gained=41. A layout change fixed 41 CORRECTNESS divergences on a target its author was not looking at, the mechanism is unknown, and an unrelated layout change could take all 41 back."
---

# A perf commit silently fixed 41 xtensa/windowed divergences

## The bisect

Two compilers, both self-host fixedpoints (`converged after N round(s)`, shas
confirmed different from `pinned`), swept against the **same** 129 sources and
the same `lib/rtl` on the same box, so the compiler is the only variable:

| build | windowed MATCH |
| --- | --- |
| `75d2ba662^` (`41e452a55913`) | **53** |
| `75d2ba662` (`a3f0f9e3325f`) | **94** |

`lost=0, gained=41`, totals cross-checked against the row sets. Nothing later in
the range moves it: `658f4bea5` and `10c869750` both sit above `75d2ba662` and
measure 94, and the current HEAD also measures 94.

## What the commit says it does

> *perf(O): page-separate code from data in the ELF writer — 287x under qemu*
>
> A hot write to a word that shares a 4 KiB page with translated code makes a
> qemu-user-style emulator invalidate that page's translations on every store.

Pure performance, target-agnostic, and correct on its own terms. Its own gate
was a timing measurement, which is exactly the gate that cannot notice 41
programs changing their **output**.

## The 41

Almost entirely aggregate and managed shapes — records, dynamic arrays,
interfaces, variants, sets:

```
test_cross_record, test_cross_record_array_store, test_cross_dynarray,
test_dynarray_copy{,_nested}, test_dynarray_field, test_dynarray_whole_assign,
test_nested_dynarray_setlen, test_interface_arc, test_interfaces{,_as,_is,
_inherit,_param,_multi_secondary}, test_cross_variant,
test_cross_variant_payload_widths, test_variant_class_cross, test_cross_sets,
test_set_runtime, test_cross_typed_const, test_frozen_string_cross_b305, ...
```

That family is the one that goes through **data references** — RTTI descriptors,
literal blocks, typed constants. A change to where the data section begins is
plausibly connected to it. **That is a hypothesis and this ticket does not claim
it**; nobody has diffed the emitted code for one of these programs across the
two builds, which is the next step and is cheap.

## Why this is a bug ticket and not a note

**The 41 are passing for a reason nobody chose.** If the mechanism is that a
data-address shift moved something out of a range it was silently out of, then
the underlying defect is still there and is being masked by a layout property
that no test asserts. Any future change to code/data placement — a different
page size, a section added, `--emit-obj`, the ESP image layout, an alignment
tweak — can take all 41 back with no diagnostic and no obvious culprit, and
whoever lands it will look responsible for a regression they did not cause.

Note the ESP angle specifically: the padding follows a 4096-byte constant, and
the commit's own comment says a host with 16 KiB pages would still leave a
residual shared page. An ESP image is not laid out like a hosted ELF at all.

## What to do

1. Pick one of the 41 — `test_cross_record` is small — and diff the emitted
   xtensa code at `75d2ba662^` vs `75d2ba662`. If the instruction stream is
   identical and only addresses moved, the defect is an address-range or
   alignment sensitivity and is still live.
2. Name it, file it, and give it a test that asserts the property directly
   rather than relying on the page padding to keep it true.
3. If instead the two streams differ, then the ELF writer was feeding codegen a
   wrong data base and this was a real fix — in which case say so on
   `75d2ba662`'s ticket, because it is recorded as a perf change and its
   correctness effect is undocumented.

## Provenance

Found while confirming the attribution of a windowed jump the coordinator and I
initially disagreed about. Neither of us was right from reasoning: the
coordinator attributed it to frankS's seven xtensa commits by file ownership,
frankS attributed it to "other lanes" — it is one commit by neither route, and
only the bisect said so. **A saved binary that brackets your own commits does
not bracket what those commits were REBASED onto**, which is what made the first
answer look settled.

## Gate

Whatever the mechanism turns out to be, the windowed differential must stay at
94 or better, and the property that keeps the 41 green must be asserted by
something other than the page padding.
