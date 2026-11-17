---
track: ESP
tags: [xtensa, dce, size, busybox, emit-obj]
prio: 4
type: feature
blocked-by: []
summary: "On xtensa, DCE now removes a dead body's closing RETW and the 3-byte NOP padding after it. The frontends record a body's end just before that RETW, so every dropped body used to leave `retw.n; nop; nop` in the always-live gap. An empty --shared-runtime no-main object went from 4,740 to 1,252 B of code (2,097 B of NOPs before, 81 after). Also, an object whose source never says `main(` gets a bare `entry; retw` weak app_main instead of the full process entry."
status: done
owner: unassigned
---

# xtensa DCE drops a dead body's closing RETW and padding

pxx2 measured the per-object floor for BusyBox (182 TUs) at ~4.7 KB. `--dce-why` showed only ~680 B of live procs. The rest was filler that sat outside every body.

## Cause
DceBodyEnd uses ProcBodyEnd, which the frontends record before the closing RETW. SetProcBodyAddrHere then pads the next body to 4-byte alignment with 3-byte NOPs. So each removed body left 2 + 3k bytes behind, ~550 times per object.

## Fix
- dce.inc DceBodyEnd, xtensa only: when the recorded end is not 4-aligned, claim a following `retw.n` (1D F0) or `retw` (90 00 00) and then 3-byte NOPs, but only if that lands exactly on a 4-aligned offset within the slot's limit. Otherwise nothing changes. The compaction therefore still moves code by multiples of 4, which keeps L32R literal words aligned.
- cparser.inc, windowed posix object entry stub: when CTokensMentionMain is false (no `main (` anywhere in the TU), emit only `entry a1,32; retw`. The weak app_main of a no-main object is never entered.

## Measured (empty TU, --shared-runtime, windowed)
code 4,740 → 4,608 (stub alone) → 1,252 B (with DCE). The remaining ~700 B is __fini_pxxcio's chain (see the follow-up in bug-xtensa-shared-runtime-objects-skip-atexit-handlers).

## Verified
gate quick, test-xtensa, test-esp-bare, test-esp-softfloat, and the xtensa test-core rows run directly.
