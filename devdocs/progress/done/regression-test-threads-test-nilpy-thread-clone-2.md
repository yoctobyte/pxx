---
prio: 70
track: A
status: done
owner: frankb-78
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 6 is `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"`. The job's own `src` (`test/test_nilpy_thread_clone.npy`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_nilpy_thread_clone.npy at 08f7de0715a8 in step 2/6, `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T16:04:12Z
- **Test source:** test/test_nilpy_thread_clone.npy tools/expect_same.sh +2
- **Failing step:** line 2 of 6 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_nilpy_thread_clone.npy'` at 08f7de0715a8a9cf5f2e739231b7ac7d2b18177f

## Range
> **The named sha `08f7de0715a8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `08f7de0715a8`, last good `8476a5157557`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2784241/test_npy_clone26  [code=1347352B  data=77376B  bss=51404B  procs=1928]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_npy_clone26]
--- expected
+++ actual
@@ -1,2 +1 @@
 tid nonzero = True
-child ran = 7

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 5ad048c2d9ae (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 9cf9771387c6 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 72184098b614 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at afbc83e5a976 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 7fff15ddc1eb (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 88807c8258fe (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 7c32e3fee9ce (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at c8375f3e76e9 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.


## NOT A REGRESSION — measured on the pin, 2026-09-02 22:2x (frankuser)

**It fails at the same rate on a compiler that predates every commit in the
range, so no bisect of that range can find it.** Interleaved A/B, 45 runs each,
same host, same minute, alternating to control for load:

| binary | commit | failed |
| --- | --- | --- |
| tip `a81084690bac` | `ba90811d3` | **1/45** |
| pinned `1eec4dc5e0a7` | pin v399, predates the range | **1/45** |

Built both with `--threadsafe` (the test refuses without it) from
`test/test_nilpy_thread_clone.npy`; failures are SIGSEGV (rc=139), and the
crash lands **before the first line finishes printing** — output truncates at
`tid nonzero =`.

**So this is a rare intermittent in thread startup, roughly 2%, not a defect
introduced by anything in the bisect range.** Tonight it was re-filed as
`NEW-RED` against `51b80e55be90`, a **docs-only** commit, and the only
compiler-touching files in that 21-commit range were `compiler/ir.inc` and
`compiler/symtab.inc` — the frozen-string fix, which is innocent here. Two
separate auto-filings (16:04 and 20:07) at unrelated shas is itself the
signature of an intermittent rather than a regression.

**Why a single-run watcher cannot see this.** At ~2%, one run per sha passes 49
times in 50, so the test reads as green until it doesn't, and whichever sha
happens to catch it gets blamed. `flaky: 0` in the report means *not classified*
flaky, not *measured* not-flaky.

**Re-laned T → A.** The ticket's own header says the T tag is a fallback because
the failing step named no owner; a SIGSEGV in cloned-thread startup is Track A.
Plausibly related: `feature-a-tls-stack-bounds-for-cloned-threads` and
`bug-a-test-tthread-fails-under-full-tier-load-but-never-in-isolation` — that
last one is the same shape (a threads test failing only under load).

**The bug is real; only the attribution was wrong.** ~2% of `__pxxclone` starts
segfault before the parent completes a write.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 26db8523e829 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-03 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at c23dcf1cfd42 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-03 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at cd694bdc4de9 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-03 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at a24a521145b0 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-03 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 35b96158ce91 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.


## RE-VERIFIED AT HEAD 2026-09-03 (frankB): still red, and it is a SEGFAULT

`43e8edb74`, native x86-64, `--threadsafe`, the Makefile's own two lines:

```
100 consecutive runs of $(TESTTMP)/test_npy_clone26
  nonzero rc: 29        all of them rc=139 (SIGSEGV)
  output when it dies:  "tid nonzero =" or "tid nonzero = True", truncated
```

So the failure is a CRASH in the child-thread path, not a wrong value, and the
expected output is produced right up to the point where it dies.

**MY FIRST TEN RUNS WERE ALL GREEN AND I ALMOST REPORTED IT FIXED.** Ten passes
against a ~29% per-run failure rate is a 3% event, and I had already typed
"10/10 green at HEAD" before running more. `f3cb2cb3c` refused to close this on
ONE green for exactly this reason and was right; ten is not different in kind.
**A race gets a failure RATE, never a verdict** — and the rate is the number to
put in a ticket, because it is the only thing that makes the next reader's
sample interpretable.

Not diagnosed further: parked here rather than microfixed, and NOT closed. The
lane is still wrong on the frontmatter (Track T by fallback, and the failing step
named no owner); the defect is in the thread-clone path, so it is A or N.

## FIXED (frankB, 2026-09-03) — the trampoline never set the hidden-destination register

**Re-laned T → A** (the fallback said T because the failing step named no owner;
the defect is in the clone stub, `compiler/thread_emit.inc`).

### What it actually is

`__pxxclone`'s trampoline calls an entry it knows nothing about. A callee whose
return type is `RetViaHiddenDest` — a record, a set, a frozen string, a Variant,
a promo int — does not return its value in a register: it copies it through a
pointer **the caller is obliged to hand it**, in a register fixed per target
(r10 on x86-64, ecx on i386, x8 on aarch64, r12 on arm32; `EmitAggregateDestStash`
is the other end). **The stub set none of them.** So the child copied its result
through whatever the clone syscall sequence had left there — on x86-64 that
register is r10, which the stub loads with `ctidptr` for the syscall, so
`__pxxclone(..., 0)` made the child write 16 bytes to address 0.

**Every NilPy `def` is such an entry.** They all return a Variant. The gdb frame
is one line: `worker + 172: rep movsb (%rsi),(%rdi)` with `rdi = 0`, in thread 2,
at the `return` — the epilogue's result copy.

### Why it read as intermittent, and why nothing else caught it

The child's crash races the parent's exit. The parent usually finishes and
`exit_group`s first, so the process dies before the child reaches its epilogue.
Sharpen the race and the intermittent becomes deterministic — with the worker's
body emptied so the parent spins the full 400M instead of exiting early:

| variant | fails |
| --- | --- |
| the test as written (worker sets `ran`, parent exits early) | 19/60, then 29/100 |
| worker returning immediately, parent spinning | **40/40** |
| the same with `arg` pointed at valid memory | 40/40 (it is r10, not arg) |

**No Pascal thread in the tree has this shape**: `TThreadEntry` is a
`procedure`, so every existing thread returns nothing and never reads the
register. A whole ABI obligation was unexercised because one frontend's threads
are all procedures and the other frontend's are all functions.

### The fix

The stub carves a `CLONE_RETBUF_SIZE` (256-byte) scratch off the top of the
child's stack — above the alt stack, so every other offset in the leg is
unchanged — and points the hidden-destination register at it before calling the
entry. An entry with no result ignores the register; one with a result writes
into a sink the child discards by exiting, which is the only meaning available
(the child never returns).

Four legs, four registers. **And converting two hand-counted branch offsets,
which is not incidental**: the aarch64 `cbnz x0, .parent (+7 words)` and the
arm32 `bne .parent (+7)` were counted by hand over the child sequence, and
adding one instruction to that sequence made both land one instruction short —
inside the child path, in the parent. The x86-64 and i386 legs had already been
converted to computed offsets for exactly this reason and these two had not, so
the file carried the warning and the bug at once.

### Verified — and the positive control is the interesting part

New `test/test_clone_entry_with_a_hidden_result.pas`: record, set, frozen-string
and void entries through `PalThreadCreate` (the PAL owns the stack mmap and the
syscall numbers, so one source runs on every threading target).

**"Did it crash" was the wrong instrument and this is the reusable part.**
Scribbling over a join handle is usually SILENT — `munmap` of a garbage range is
ignored and the kernel clears the tid word afterwards anyway — so a
survival-only row passed 70% of the time on a compiler that was corrupting
memory on every run: 5/20, then 9/30 with a result four times wider. The
assertion has to be on **the memory the stray pointer aims at**:
`PalThreadCreate` passes `@h.TidWord` as ctidptr and `StackSize` sits 16 bytes
past it, so the test snapshots `StackSize` while the children are still spinning
and compares it after the join. That fails **10/10** on the pinned compiler —
and half of those runs HANG rather than crash, which is the other reason the
crash-only row was the wrong shape.

| | fixed | pinned (pre-fix) |
| --- | --- | --- |
| x86-64 | 25/25 pass | **10/10 fail** (5 hang, 5 report `handles intact 0 / 4`) |
| i386 | pass | **SIGSEGV** |
| aarch64 | pass | **SIGSEGV** |
| arm32 | pass | **passes 5/5** |

**arm32's control does not fire and the row says so.** r12 is untouched by that
leg's syscall sequence, so it holds whatever the caller left — which happened to
be valid here. That row is regression cover, not a reproduction, and reading it
as one would be reading a green as a proof.

The originating test: `test_nilpy_thread_clone.npy` **0 failures and 0 wrong
outputs in 200 runs**, against 29/100 measured at `43e8edb74` this morning.
Existing thread coverage re-run on all four legs: `test_tthread` and
`test_mutex` on i386, `test_tthread` and `test_parallel_for_lang` on aarch64 and
arm32 — all pass, which is what says the branch-offset conversion is right.

### Filed, not fixed here

- [[bug-a-a-nilpy-clone-entry-receives-a-raw-word-where-it-expects-a-variant-address]]
  — the ARGUMENT half of the same ABI mismatch. A NilPy parameter is a by-ref
  Variant, so a worker that actually READS `arg` dereferences the raw word:
  3/3 SIGSEGV. The stub cannot fix that one; it needs a thunk where the callee
  is known.
- [[bug-a-nilpy-thread-clone-cannot-start-a-thread-on-aarch64-or-arm32]] —
  `tid nonzero = False` on both, at the pin as well, so not a regression.
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
