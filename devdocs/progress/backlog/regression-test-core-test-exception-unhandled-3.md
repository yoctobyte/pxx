---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 53 of 47 is `/tmp/next-test_multithreading26 | grep -q "multithreading test completed successfully"`. The job's own `src` (`test/test_exception_unhandled.pas`, 13 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_exception_unhandled.pas@3 at 3d4801b6abc3 in step 53/47, `/tmp/next-test_multithreading26 | grep -q "multithreading test completed successfully"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T21:59:42Z
- **Test source:** test/test_exception_unhandled.pas compiler/compiler.pas +11
- **Failing step:** line 53 of 47 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  /tmp/next-test_multithreading26 | grep -q "multithreading test completed successfully"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_exception_unhandled.pas@3'` at 3d4801b6abc305d803228ec381394834336b8b40

## Range
> **The named sha `3d4801b6abc3` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3d4801b6abc3`, last good `889bfcf73256`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
134]
ok: /tmp/testmgr-scratch-3028389/self-records26  [code=69400B  data=2792B  bss=43540B  procs=134]
ok: /tmp/testmgr-scratch-3028389/self-procs26  [code=69400B  data=2888B  bss=43496B  procs=137]
ok: /tmp/testmgr-scratch-3028389/self-string_compare26  [code=69400B  data=2960B  bss=43500B  procs=136]
ok: /tmp/testmgr-scratch-3028389/self_record_string_field26  [code=69400B  data=2900B  bss=43524B  procs=135]
ok: /tmp/testmgr-scratch-3028389/self-test_heap26  [code=69400B  data=2792B  bss=43504B  procs=134]
ok: /tmp/testmgr-scratch-3028389/self-test_multithreading26  [code=69288B  data=3988B  bss=43556B  procs=138]
ok: /tmp/testmgr-scratch-3028389/self-test_math_unit26  [code=224936B  data=6648B  bss=43576B  procs=675]
ok: /tmp/testmgr-scratch-3028389/self-fileio26  [code=110360B  data=5032B  bss=43788B  procs=248]
pascal26:5758: warning: bare own name 'TargetDisplayName' reads the result of parameterless function TargetDisplayName; write TargetDisplayName() for a recursive call, or Result to read the result
ok: /tmp/testmgr-scratch-3028389/pascal26-next.3029288.tmp  [code=9805592B  data=480952B  bss=103315116B  procs=3973]
ok: /tmp/testmgr-scratch-3028389/next-hello26  [code=65304B  data=2840B  bss=43492B  procs=134]
ok: /tmp/testmgr-scratch-3028389/next-bootstrap_features26  [code=69400B  data=2920B  bss=43508B  procs=134]
ok: /tmp/testmgr-scratch-3028389/next-records26  [code=69400B  data=2792B  bss=43540B  procs=134]
ok: /tmp/testmgr-scratch-3028389/next-procs26  [code=69400B  data=2888B  bss=43496B  procs=137]
ok: /tmp/testmgr-scratch-3028389/next-string_compare26  [code=69400B  data=2960B  bss=43500B  procs=136]
ok: /tmp/testmgr-scratch-3028389/next_record_string_field26  [code=69400B  data=2900B  bss=43524B  procs=135]
ok: /tmp/testmgr-scratch-3028389/next-test_heap26  [code=69400B  data=2792B  bss=43504B  procs=134]
ok: /tmp/testmgr-scratch-3028389/next-test_multithreading26  [code=69288B  data=3988B  bss=43556B  procs=138]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 866bb0b262f9 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-3`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 45f28a23d12d (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-3`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## Does NOT reproduce on plexus, on EITHER compiler — 2026-09-02, frankZ

Run under the umbrella [[umbrella-one-full-tier-run-with-no-red-tier]], with
the recipe's own flags:

| binary | commit | runs | failures |
| --- | --- | --- | --- |
| `480d4584403c` (HEAD) | `ad55e4dcc` | 40 | **0** |
| `stable_linux_amd64/default/pinned` (v399) | 2026-08-19 | 30 | **0** |

Two independently built compilers, byte-different programs, 70 runs, no
failure. The tested sha `3d4801b6abc3` is also an upper bound rather than a cause —
the ticket's own banner says it touches no buildable file.

**This is half a finding and the residual belongs to Track T.** "Not
reproducible on plexus" does not answer "then why is it red on seven", and I
cannot answer that from here: **seven runs this job under full-matrix
parallelism and I ran it solo.** For a threading-adjacent program that is not
a detail, it is the most likely difference — the same shape as
`test_multithreading`, which needed no load to fail but whose rate moved with
it.

What would settle it, and what I am NOT claiming to have done: the same job on
seven, under load, at this sha. Left open and wired to the umbrella rather than
resolved, because a red nobody can reproduce is still a red in the tier that
decides whether a pin is green.

## MEASURED: this is a FLAKE, and the tstate archive says so outright (frankZ, 2026-09-02)

The earlier entry on this ticket said the failure does not reproduce here on
either compiler and named seven's full-matrix parallelism as the likeliest
difference. That was half a finding. Here is the other half, and it does not
depend on reproducing anything.

**Track T's own markers alternate.** Counting every tstate commit subject that
names `test_exception_unhandled`:

```
NEW-RED-bearing commits : 10
FIXED-bearing commits   : 11
total markers           : 24
18 of the 24 markers land on 2026-09-01 alone
```

**A regression cannot be fixed and re-broken 10 times in one day.** That would
need 10 fixes and 10 breakages, on one host, across shas that mostly touch
docs and tickets. The only reading left is that the job's verdict is
**nondeterministic**, and the NEW-RED / FIXED pairs are the watcher faithfully
reporting a coin landing differently.

This is a second source that FAILS DIFFERENTLY from the local non-reproduction:
0-in-40 here is consistent with "rare flake" AND with "host-specific bug", and
cannot separate them. The alternating markers separate them — a host-specific
bug is stable on its host, and this is not stable on its host.

## What changes because of it

- **It is not a regression, so there is no cause in any commit range**, and the
  auto-filed range is not merely unnarrowed, it is meaningless. Nobody should
  bisect this.
- **The right work is to stabilise or quarantine the test, not to find a
  breaking commit** — and if the nondeterminism is a real race in the program
  under test rather than in the harness, that race is the ticket, at a much
  higher value than this one.
- **The residual owner does not change**: Track T, named above, now with a
  measurement instead of a hypothesis.

## Why it matters to the umbrella specifically

[[umbrella-one-full-tier-run-with-no-red-tier]] wants ONE full run with no RED
in any tier. **A test that flips on its own makes that a lottery** rather than a
consequence of fixing things: every arrival can be beaten by the fix rate and
the run still comes back red. Recorded there too.
