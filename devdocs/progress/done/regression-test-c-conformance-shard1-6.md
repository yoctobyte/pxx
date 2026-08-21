---
prio: 70
status: done
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-conformance#shard1/6 red at 1b9b43e5b511 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T16:41:34Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance#shard1/6'` at 1b9b43e5b511d53e9fbe55f3366e6ce9158ee0b9

## Range
bad `1b9b43e5b511`, last good `57b9b7148d32`, 132 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00206.c — exit code 254 (want 0)
FAIL 00212.c — exit code 252 (want 0)
test-c-conformance: 35 pass, 2 fail, 0 skip (of 37)
test-c-conformance: FAILURES: 00206.c(exit=254) 00212.c(exit=252)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause found and fixed — 2026-08-21 (agent-A)

Real, reproducible, and nothing to do with the commit it was blamed on
(`e96a698f1` / `1b9b43e5b511` are ticket edits): **00206.c and 00212.c both end
`main` without a `return`.**

C99 5.1.2.2.3 says reaching the closing brace of `main` is `return 0`. pxx
returned whatever the uninitialised result slot happened to hold. Both programs
printed EXACTLY the expected output and then exited 255 and 253 here — while the
watcher recorded 254 and 252 for the same two tests. Two builds, two different
wrong numbers, right output: that is stack garbage, and it is why the shard
looked like it changed behaviour at a commit that changed no code.

Fixed by zeroing main's result slot in the prologue (cparser.inc), which leaves
an explicit `return n` winning because it stores over it, and covers every way
of reaching the brace — fall-through, out of a nested block, a `goto` to a
trailing label.

Uncovered on the way: `EmitZeroLocalSlotForTarget` emitted **nothing** for a
4-byte slot on the 64-bit targets (`4 div 8` = 0), which is exactly the size of a
C `int` result. Both 64-bit arms now finish with a 4-byte store. Rounding up to
8 would have been worse than nothing — a 4-byte local is 4-aligned with the next
local immediately above it.

Verified: shard 1/6 is **37 pass, 0 fail** natively AND on aarch64, arm32,
riscv32 and i386 under qemu. Regression guard added as `test/c_main_no_return.c`
with a Makefile row that checks the EXIT STATUS (the only visible symptom):
straight-through, out of a nested block, and via a goto to a trailing label,
byte-identical to gcc -std=c99 and exiting 255 on the pre-fix compiler.
- 2026-08-21 — resolved, commit PENDING-COMMIT.
