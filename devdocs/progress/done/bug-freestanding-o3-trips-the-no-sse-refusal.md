---
slug: bug-freestanding-o3-trips-the-no-sse-refusal
track: C
prio: 30
type: bug
status: done
created: 2026-11-23
found-by: claude-pxx (measuring the Rainyday pc kernel at -O3)
tags: [x86-64, freestanding, optimiser]
blocked-by: []
summary: "No --freestanding program built at -O3: FloatPoolBoundaryAssign turned the xmm8..13 pool wrap on for every -O3 x86-64 body, and the wrap's movq around pxx's own RTL indirect call (platform.pas PalDrainPending) tripped asmtext's no-SSE refusal. Fixed: the pool stays off where that refusal applies."
---

# --freestanding at -O3 did not build

Found 2026-11-23 while measuring whether -O3's store->reload elimination
would shrink the Rainyday pc kernel. Every C file failed:

    pascal26:978: error: --freestanding: float/double arithmetic is not supported
      in: lib/rtl/platform.pas  near: PalPendingDrain <> nil then PalPendingDrain

The x86-64 -O3 path reserves and wraps an xmm8..13 save around calls whose
target may not honour pxx's callee-saved xmm convention (FloatPoolSave). The
wrap emits xmm moves; asmtext refuses any xmm text under --freestanding.

## Fix

FloatPoolBoundaryAssign exits when AsmFreestandingRefusesSSE, the refusal's
own predicate: freestanding code has no floats, so there is nothing in the
pool to protect. The appended builtin units are exempt from the refusal and
keep their wraps.

Result: the Rainyday pc kernel builds at -O3 and boots. It is larger than
at the default -O2 (text 1626396 against 1589910), so -O3 is not a size
lever for it.

Test c_freestanding_o3_builds.c, row c_fso326; it fails with the compiler
from before the fix.
