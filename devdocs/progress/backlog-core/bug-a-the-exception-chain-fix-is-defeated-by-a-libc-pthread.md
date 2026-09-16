---
slug: bug-a-the-exception-chain-fix-is-defeated-by-a-libc-pthread
track: A
prio: 70
type: bug
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: [decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part]
summary: "`bug-a-the-exception-shadow-chain-is-process-wide-so-two-threads-crash` moved TLS_SLOT_EXC_TOP into the per-thread TLS block, and its own note says a fresh thread gets a ZEROED block from the clone stub. A libc pthread never runs that stub, so it INHERITS a chain head pointing at its creator's live frames -- and the fix is defeated for exactly the thread kind DOSBox, SDL and every threaded C library create. MEASURED: main thread and one pthread_create'd thread each doing 300k try/except, 3 runs of 3 print `Unhandled exception`; the identical 600k of work on ONE thread in the SAME binary is 3 of 3 clean. At 2k each, one run of three produced no output at all. Repro is test/test_foreign_thread_exception_chain.pas, NOT WIRED because it fails -- AND ITS EXIT CODE IS A COIN FLIP AT A FIXED LEVEL WITH A FIXED BINARY, which is the part that decides how to verify a fix: 30 runs at -O2 (2026-09-16) gave 0 x5, 124 x1, 139 x1, 217 x23, and 30 at -O0 gave 139 x3, 217 x27. IT PASSES ABOUT ONE RUN IN SIX AT -O2, so a single-run verification of any fix here reads FIXED on luck at that rate; verify over >=30 runs per level and report the distribution. tools/optdiff.skip carries the file because optdiff enumerates every source file under the test directory and swept a program the suite deliberately excludes -- that skip is on the INSTRUMENT and this bug is untouched and open."
---

# A libc pthread inherits its creator's exception chain

## RE-MEASURED 2026-09-16 -- THE REPRO IS A COIN FLIP, AND ONE RUN CANNOT VERIFY A FIX

Everything below this section stands. What it does not say, and what anyone who
works this ticket needs before they start, is that **the repro's exit code is
nondeterministic at a FIXED optimisation level with a FIXED binary** -- and one
of its outcomes is SUCCESS.

Measured 2026-09-16, compiler `b57f90696a01`, `--threadsafe`, 30 runs per level,
one binary per level built once:

| level | exit 0 | 124 (timeout) | 139 (SIGSEGV) | 217 (unhandled exception) |
| --- | --- | --- | --- | --- |
| `-O0` | -- | -- | 3 | 27 |
| `-O2` | **5** | 1 | 1 | 23 |

**The row that matters is `-O2` exit 0: the repro PASSES about one run in six.**
So a future fix for this ticket, verified the ordinary way with a single run,
has roughly a one-in-six chance of reading as FIXED on luck alone -- and the
same coin decides whether a REGRESSION is seen. **Verify any change here over
at least 30 runs per level and report the distribution, never a single exit
code.** The 139 and 124 rows say the same thing from the other side: this
defect's observable is not one behaviour but four, and a ticket that says only
"prints `Unhandled exception`" under-describes it enough to mislead.

Found from the other end, by frankuser, because `optdiff#shard9/12` went red
naming a 12-commit range with no cause in it. The mechanism is a population
error in the harness: `tools/optdiff.sh:122` enumerates every `.pas` and `.c`
file under the `test/` directory, so this program is swept even though its own
summary says it is NOT WIRED because it fails. That population is "files in
`test/`", not "tests". A one-run-per-level differential cannot express a
question about a program whose exit code is a coin flip, so `tools/optdiff.skip`
now carries it; **the skip is on the INSTRUMENT and this bug is untouched and
still open at p70**, which is the right split and is recorded here so nobody
reads the skip as a downgrade. The auto-filed regression ticket naming that
range was corrected and moved to `rejected/` -- nothing in the range is causal,
and the PINNED v410 compiler, which predates all of it, flakes identically.

The numbers above are this seat's own runs, not a relay: the distributions
differ in detail from frankuser's (they saw outcomes at levels where I did not),
which is what a race looks like and is itself part of the finding.

## RE-MEASURED 2026-09-15 at `561c30f6409b9376` -- STILL LIVE, AND THE BLAST RADIUS IS NOW BOUNDED

Re-run because the thread-pointer work landed 2026-09-14 (`palthread.pas` now
makes threads through a weakly-imported libc `pthread_create`) and nobody had
re-measured this against it. **A parked test whose blocker may have moved is
worth one command**; this one had not moved, but the SCOPE turned out to be
much narrower than the ticket as written implies, and that is the new
information.

```
raw pthread, 300k each   5 runs: 4x "Unhandled exception",
                                 1x main=-967549 worker=222 FAIL: counts
same loop, NO thread     3 runs: main=300000 CTL OK   (3 of 3)
```

**TWO THINGS THE ORIGINAL MEASUREMENT DID NOT RECORD.**

**1. The CREATOR is broken too, not just the new thread.** `main=-967549` is the
`-1000000` sentinel the fixture writes when the `try` body does NOT raise, plus
later increments -- so the main thread's own `try/except` stopped working, in a
process where it had been perfect moments before. The no-thread control is the
same loop in the same binary and is exactly 300000, three times. Creating the
foreign thread is what breaks the thread that created it. That follows from the
mechanism (they SHARE one chain head) but it was never stated, and "a foreign
thread is broken" reads as though the rest of the program is fine.

**2. PXX'S OWN THREADS ARE NOT AFFECTED. Measured, not assumed:**

```
NilPy `import threading`, Thread(target=worker), 50k try/except per row
  before=50000  during=50000  worker=50000  after=50000   3 runs of 3
CPython oracle: identical
```

The boundary is `PxxPthreadStart` (`palthread.pas`), the start routine glibc
calls for a PAL-made thread: it installs pxx's own `gs` block before running the
entry, doing for a pthread-made thread exactly what the clone stub's child leg
does for a cloned one. **A thread created THROUGH the PAL therefore gets a
zeroed chain head and is correct. A thread created by USER CODE declaring its
own `external 'libpthread.so.0'` never runs that routine and never gets a
block** -- which is precisely this bug, and precisely the fixture's shape.

**So the population is user-written raw-pthread code and threaded C libraries
(DOSBox, SDL), NOT `threading`, `TThread`, or anything using the PAL.** Worth
stating plainly because the summary's "every thread kind DOSBox, SDL and every
threaded C library create" is correct and is easily read as "every thread",
which would make it a much bigger and much more urgent bug than it is.

This does NOT lower the prio: the named consumers are real targets. It bounds
what has to be re-verified when the `decide-` is answered.


Measured 2026-09-02 at `efc33772a`.

## The measurement, with its control

`test/test_foreign_thread_exception_chain.pas` — main thread and one
`pthread_create`d thread, each running `try Boom; except Inc(n) end` in a loop,
counting.

```
foreign thread, 300k each   run1..3: Unhandled exception
same work, ONE thread, 600k run1..3: main=300000 worker=300000 FOREIGNEXC OK
foreign thread, 2k each     run1: OK   run2: (no output at all)   run3: OK
```

The single-threaded row is the control and it is drawn from the same binary and
the same code path — the worker function is called directly instead of through
`pthread_create`. So this is the thread, not the loop.

## Why the existing fix does not cover it

`defs.inc`'s note at `TLS_SLOT_EXC_TOP` states the mechanism exactly:

> A fresh thread gets a ZEROED block from the clone stub, i.e. an empty chain,
> which is exactly right and is the other half of the fix.

**A foreign thread never runs the clone stub.** `clone` does not reset `gs`, so
it starts life pointing at its creator's block with the creator's chain head in
it. Thread A's `try` then links onto thread B's frame and a raise longjmps into
a frame that may already be dead — which is the same sentence that ticket used
to describe the bug it fixed.

This is the concrete, crashing instance of
[[bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine]]. That ticket
is right that the general question is a design decision; this one is not a
design question, it is a program that fails.

## What is already in place, and it is more than the parent ticket says

The parent lists "detect and install lazily" and dismisses the detection half:
*"the block's self-pointer at slot 0 does not work ... a gettid comparison needs
a syscall or a cached value with the same bootstrap problem."*

**That was solved and shipped.** `feature-a-io-lock-owner-from-tls-not-gettid`
established the discriminator inheritance cannot fake — the reader's own `rsp`
against the bounds the block's owner recorded — and it is live in
`ir_codegen.inc:1099-1118`, guarding the I/O lock's cached tid. The parent's
option analysis is stale about its own hardest sub-problem.

So the missing half is not detection. It is **where a foreign thread's block
comes from and what bounds go in it**, which is the decision this is blocked on.
