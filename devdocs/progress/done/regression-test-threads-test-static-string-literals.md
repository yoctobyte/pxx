---
prio: 70
track: T
status: done
owner: frank-optimize-b4
---

> **Track T by default, because this job TIMED OUT.** The source path says what a job compiles, not what went wrong, and a timeout did not fail in any of its sources — it ran out of budget. Guessing a lane from the path is the wrong turn `bug-t-a-timeout-bisects-to-an-innocent-commit` was filed to stop, so a timeout stays T's until someone shows otherwise. Re-lane it if the budget was not the problem.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_static_string_literals.pas@2 red at 5bb3e120d3f7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T04:25:16Z
- **Test source:** test/test_static_string_literals.pas tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_static_string_literals.pas@2'` at 5bb3e120d3f7e9f32452b1bf462f9f07fc7f5832

## Range
> **The named sha `5bb3e120d3f7` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5bb3e120d3f7`, last good `0c99981669b7`, 8 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-307305/test_ssl026  [code=87344B  data=3680B  bss=42524B  procs=132]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 — TRIAGED and closed by frank-optimize-b4 (Track O, the test's author)

Real, mine, and **not a threading bug despite the tier it fired in** — the job
timed out because the aarch64 arm of this test took **99 seconds** under
qemu where it takes 1.2s at -O0 and 0.008s natively on x86-64.

The cause is filed with its full measurement as
[[bug-a-a-hot-write-to-a-data-page-that-shares-with-code-costs-1600x-under-qemu]]:
the static string literal's refcount word can land on the same 4 KiB page as
translated code, because `elfwriter.inc` emits one RWX PT_LOAD with data
immediately after code — and a hot write to such a page makes a qemu-user-style
emulator invalidate its translations on every store. The same binary is fast
natively; an x86-64 build run under `qemu-x86_64` shows the identical cliff at
**1600x**, which is what proves it is emulation and layout rather than aarch64
codegen.

The watcher's own banner was right twice over, and worth crediting: it said a
timeout is not a source failure and stays Track T until someone shows
otherwise, and it said the named sha touches no buildable file so the cause is
below it. Both held. What the path *did* correctly indicate is which test to
look at — just not which lane owned it.

Fixed here by making the loop count target-conditional (200,000 native, 2,000
emulated), which restores the arm to ~1.07s. That is not the cliff being
hidden: the count was never part of what the row asserts, and all four arms
still produce byte-identical output against one expectation.

### The watcher auto-closed this while it was being triaged, and that is evidence

The plexus watcher closed it on `0f0a5619a413` passing (tier native) after it
was red at `5bb3e120d3f7`. Nothing was fixed in between. **That is the cliff's
signature, not its absence:** the cost depends on whether the literal's
refcount word shares a page with code, so any commit that changes the code size
flips it, and the same test passes and fails across unrelated commits. A
watcher that reopens by fresh NEW-RED stub will therefore keep re-finding this
with a new range each time until the layout ticket lands. Read a future stub
against the same source as this one, not as a second finding.

## Log
- 2026-08-30 — auto-closed by the plexus watcher: `test-threads#src:test/test_static_string_literals.pas@2` passes at 0f0a5619a413 (tier native); it was red at 5bb3e120d3f7. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
- 2026-08-30 — triaged by the test's author, cause filed as a separate Track A bug, test fixed; commit a640b1233.
