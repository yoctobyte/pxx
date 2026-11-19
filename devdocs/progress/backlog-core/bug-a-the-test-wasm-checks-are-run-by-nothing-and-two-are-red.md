---
track: A
tags: [wasm32, test-infra, gate]
prio: 45
type: bug
status: open
owner:
blocked-by: []
summary: "test/wasm/ has 46 check scripts and a check_all.sh runner, and no Makefile target or gate step runs any of them. check_nilpy_generator_slot sat RED for months that way (fixed 2026-11-19). Two are red today and were red on the 10-31 build: check_phase1 (test/wasm/wasmenc_selftest.pas no longer compiles: `undefined variable (OutOpen)` in compiler/wasmenc.inc:1770) and check_exc (test/wasm/exc_slice.pas SEGFAULTS when built NATIVELY for x86-64, before wasm is even involved). Fix both, then wire check_all.sh into a suite."
---

# The test/wasm checks are run by nothing, and two are red

Measured 2026-11-19 by claude-dupwt at the tree that fixed
bug-a-a-nilpy-generator-slice-faults-out-of-bounds-under-wasm32:
42 of 46 scripts exit 0. The red ones are:

| script | rc | cause | red on 10-31 build? |
| --- | --- | --- | --- |
| check_all.sh | 1 | the two below | yes |
| check_phase1.sh | 1 | wasmenc_selftest.pas: `undefined variable (OutOpen)` (compiler/wasmenc.inc:1770) | yes |
| check_exc.sh | 139 | exc_slice.pas, built for x86-64, segfaults | yes |
| wat_oracle.sh | 2 | a helper that needs arguments, not a check | n/a |

`grep -n test/wasm Makefile tools/gate.sh` finds only a comment. A check
nobody runs reports nothing, and that reads as green.

## Order

1. check_exc first. A native x86-64 segfault in an exception slice is a
   real defect outside wasm.
2. check_phase1: the selftest includes the encoder directly, so it needs
   whatever replaced OutOpen.
3. Then add `sh test/wasm/check_all.sh` to a suite that runs per change. It
   needs node and wasm-validate, so a box without them should skip it with a
   message.
