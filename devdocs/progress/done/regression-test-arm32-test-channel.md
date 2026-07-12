---
prio: 70
---

# regression: test-arm32#src:test/test_channel.pas red at aaa58e72c1e8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T18:51:33Z
- **Test source:** test/test_channel.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-arm32#src:test/test_channel.pas'` at aaa58e72c1e8b7c2a4af9f33d89e4e6ea524027e

## Range
bad `aaa58e72c1e8`, last good `aaa58e72c1e8`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-458448/test_arm32_chan  [code=174940B  data=432B  bss=38440B  procs=143]
ok: /tmp/testmgr-scratch-458448/test_arm32_chan_x64  [code=50002B  data=456B  bss=46760B  procs=107]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED 2026-07-12 (ed106ab5) — not a coroutine bug: the canary constant

Root cause is shared by all 12 jobs in this family. `CO_CANARY = $C0DECAFE` in
lib/rtl/scheduler.pas is written and read through `PW = ^NativeInt` — SIGNED, and
32-bit on i386/arm32/riscv32 — so the high bit makes it sign-extend to a negative
on load. It only ever compared equal because the named constant was itself being
truncated to a 32-bit Integer. Commit 89366847 (a correct fix: constants above
MaxInt are now typed Int64) widened the comparison to 64 bits, and a perfectly
healthy stack started reading as clobbered -> Halt(217).

Fixed by keeping the guard below $80000000 ($4C0DECAF). `make test-i386` and
`make test-arm32` fully green.
- 2026-07-12 — resolved, commit ed106ab5.
