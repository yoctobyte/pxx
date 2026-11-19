---
track: A
tags: [wasm32, test-infra, gate]
prio: 45
type: bug
status: done
owner: claude-dupwt
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

# Fixed 2026-11-19 (claude-dupwt), same day

- **check_exc: the TEST was wrong, not the compiler.** Section G raised `b`
  twice. A handled exception is freed when its except block ends, so the
  second raise used a freed object. fpc faults on the same program (runtime
  error 216, and earlier than pxx). It now raises a fresh TBeta. pxx was
  behaving correctly natively.
- **check_phase1:** WasmSaveModule calls util.inc's OutOpen, which the
  standalone self-test cannot reach. wasmenc.inc now has a plain
  `sysopen(path, 577)` OutOpen under `{$ifdef WASMENC_STANDALONE}` only. The
  compiler's binary is unchanged (14da091ec5bb before and after).
- **Wired:** the test-wasm32 target ends with `sh test/wasm/check_all.sh`
  (140 s, 45 checks, all PASS). It prints SKIP when node or wasm-validate is
  absent. test-wasm32 itself is still in no gate tier, so whether to enrol it
  is the next question (its own Makefile note already says so).
