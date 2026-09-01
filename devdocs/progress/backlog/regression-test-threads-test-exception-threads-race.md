---
prio: 70
track: A
blocked-by: [bug-a-two-threads-raising-object-exceptions-corrupt-the-heap]
summary: "TRIAGED, do not bisect: this is not a compiler regression. decide-does-raise-of-an-existing-object-transfer-ownership settled that `raise` transfers ownership unconditionally (FPC oracle), so freeing at handler exit is the LANGUAGE and pxx is right. The test re-raises two objects created once, which is a use-after-free by that rule, and the test is what must change. Measured 2026-09-01 at 4a0dd77ef: it dies SINGLE-THREADED in phase 1 on the THIRD raise of the same object -- no threads, no TLS, no shadow chain. The rewrite needs each raise to construct, which is what walks into the blocker."
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh test_exception_threads_race26 "$(/tmp/test_exception_threads_race26)" "$(printf 'single hits=200000`. The job's own `src` (`test/test_exception_threads_race.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_exception_threads_race.pas at e7be39f9a505 in step 2/4, `tools/expect_same.sh test_exception_threads_race26 "$(/t` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T13:27:20Z
- **Test source:** test/test_exception_threads_race.pas tools/expect_same.sh
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_exception_threads_race26 "$(/tmp/test_exception_threads_race26)" "$(printf 'single hits=200000 wrong=0\ntwo hitsA=200000 hitsB=200000 wrongA=0 wrongB=0')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_exception_threads_race.pas'` at e7be39f9a505ba97da11cc237b26d13585cc3d7b

## Range
> **The named sha `e7be39f9a505` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e7be39f9a505`, last good `62e176c3c4e5`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-3200146/test_exception_threads_race26  [code=81688B  data=6312B  bss=42628B  procs=194]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_exception_threads_race26]
--- expected
+++ actual
@@ -1,2 +1 @@
-single hits=200000 wrong=0
-two hitsA=200000 hitsB=200000 wrongA=0 wrongB=0
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Re-laned T -> A, and it is NOT a race (frankB, 2026-09-01)

Hit as the only RED in a broad-tier run. Enriching rather than working it: the
crash is not in my lane's change and I did not chase it to a root cause.

**It reproduces 20 times out of 20, in isolation, with no load.** The stub and
the test's own header both frame this as a race — the header records "18 of 20
runs failed [before the fix], 0 of 20 after" and warns that a single green run
is a sampling artifact. That framing no longer applies: it is now deterministic,
which makes it far cheaper to bisect than the ticket suggests.

**Three different compilers, 20/20 each:**

    compiler/pascal26 at a544cab70 (current)                  20/20 SIGSEGV
    a compiler built from compiler/ reverted to 785928f20     20/20 SIGSEGV
    stable_linux_amd64/default/stable_pinned (Aug 30 binary)  20/20 SIGSEGV

**Scope limit, stated because it bounds the conclusion.** The second and third
rows revert or predate `compiler/` only — `lib/**` and the rest of the tree were
at current HEAD throughout. So this rules out a cause inside `compiler/` in that
range; it does NOT rule out `lib/**`, and the bisect range in this ticket should
be re-derived rather than trusted. It does mean nothing landed in `compiler/`
today caused it.

**Phase 1 passes, phase 2 crashes.** Output is `single hits=200000 wrong=0` and
then a SIGSEGV, so the single-threaded control completes and the two-thread
phase dies. The `expect_same` diff showing an empty actual is the crash, not a
wrong answer.

**The crash signature matches the bug this test was written for.** Under gdb the
stack is `0x4077db` with frames repeating one thread-stack address
(`0x7fffe7e00008`) — a return path walking into another thread's frame, which is
what `done/bug-a-the-exception-shadow-chain-is-process-wide-so-two-threads-crash`
describes ("a raise longjmped into the other thread's frame and the process
CRASHED"). That makes a regression of that fix the first hypothesis to test. Not
confirmed: the emitted binary carries no symbol table, so the addresses were
never resolved to names, and `-g -O2` did not add one. Whoever picks this up
should go through `tools/pxx-gdb.py` / `pxxrc` rather than bare gdb.

## SETTLED: the cause is 620989250 (frankB, 2026-09-01, later)

    compiler/ at 620989250^ (992aa2a20)   0/20 fail   both phases, full expected output
    compiler/ AT 620989250                20/20 fail  rc=139, empty output

Both built with `lib/**` and the test source at HEAD; only `compiler/` moved.
That is the whole bisect — no gdb, no symbols, and the thread-stack reading
below is not needed to place it.

**620989250** is `fix(A): every caught exception object leaked on every backend,
both Pascal shapes` — 90 lines of `compiler/ir.inc` in the exception path,
landing 13:18 UTC, nine minutes before the test went red.

### Two claims in the section above are WRONG. Corrected here rather than edited away.

**1. "It predates today" is false.** It is a same-day regression. From
`tstate/runs-seven.ndjson` (frank-coordinator): this job appears in 51 runs,
`new_red` in exactly one — `e7be39f9a505` at 13:27:15Z — and `still_red` in the
50 since; the run before it, `62e176c3c4e5` at 13:24:30Z, was green. A
three-minute green→red window holding exactly one code commit.

**2. The `785928f20` leg was void, and it is the reason the range looked wrong.**
`git merge-base --is-ancestor 620989250 785928f20` is **TRUE** — 785928f20 is
16:20 UTC, three hours ABOVE the suspect. So reverting `compiler/` to it KEPT
the change worth removing, and the 20/20 measured there proves nothing about
`compiler/`. I also handed that sha to another agent as the bottom of a search
interval, who bisected `785928f20..5f3c7ed75` — a range that excludes the cause.
Endpoint measurements there were all correct and simply sit above the break.

**3. The pinned-binary leg was not independent either.** Two agents ran the same
Aug-30 pinned compiler and got different symptoms (rc=139 vs rc=217) because
each ran it against their own then-HEAD `lib/**` and test source. Neither held
the moving part still, so it was never one measurement.

What survives from that section: it is deterministic, not a race (20/20 in
isolation, no load), and the test source is unchanged today.

### Where to look

NOT the slot allocation — that was my first guess and it is wrong. The diff adds
status slot 6 (`BSS_EXC_CLS`, the raised class recId) to `IRExcStoreSlot` so the
try/except lowering can tell a raised OBJECT from a raised Integer before
freeing it, and the obvious hypothesis was a process-wide BSS slot repeating the
shadow-chain bug this very test was written for. Checked and false:
`exception_emit.inc` maps `BSS_EXC_CLS` to `TLS_SLOT_EXC_CLS`, the indices
(8..11 exception, 12 magbusy, 16+ heap magazines) fit `TLS_BLOCK_SIZE = 1152`
exactly, and **620989250 does not touch `defs.inc` at all**, so the slot
allocation predates it.

That leaves the two lowering hunks: `ir.inc` ~6467 and the ~82-line one at
~13351. Note the TLS form is **x86-64 only** and gated on `ExceptionUsed`
(`StatusSlotTlsIndex` exits -1 otherwise), so the other five backends run a
non-TLS path through the same lowering.

**Authorship unresolved on purpose.** The commit carries
`session_01Hkux3cssbhbVSdw6JvJamq`, which is the session that wrote this
section — and a trailer names a SESSION, not an agent, with agents spanning
several across restarts (seven session ids against four known-active agents in
the last 8 hours). So it is recorded as "this session's id is on it", not as an
attribution.

## Mechanism found, and it is not about threads (frankB, 2026-09-01)

**`620989250` frees the caught exception object at handler exit. This test
creates its objects ONCE and re-raises them 200000 times.** The second raise
touches freed memory. Its own header states the design: "an exception that
allocates takes the heap lock on every raise, which serialises the threads and
hides the interleaving under test. Phase 3's objects are created once, before
the thread starts, and only re-raised."

The commit's premise — `raise E.Create(..)` transfers the constructor's one
reference — is true for that shape and false for `raise <an existing object>`,
where the program still owns the object.

**Threads, TLS and the shadow chain are all irrelevant.** Reproduces in 15
lines, single-threaded, 5 iterations:

    program reraise;
    type TMyErr = class Code: Integer; end;
    var obj: TMyErr; i, caught: Integer;
    begin
      obj := TMyErr.Create; obj.Code := 7;
      caught := 0;
      for i := 1 to 5 do
      begin
        try raise obj;
        except on e: TMyErr do if e.Code = 7 then Inc(caught); end;
      end;
      WriteLn('caught=', caught, ' code=', obj.Code);
    end.

    compiler/ at 620989250^   caught=5 code=7   exit 0
    compiler/ at HEAD         SIGSEGV           exit 139

My earlier thread-stack reading of the gdb frames was the wrong hypothesis and
is superseded — the repeated stack address is a consequence of the freed object,
not a shadow-chain race. Recorded rather than deleted because it is what a
plausible-but-wrong signature reading looks like: the test is *named* for a
thread race, it *had* been a thread race, and the frames were consistent with
one. The name routed the diagnosis.

**Not fixable without a decision** — `test_exception_object_leaks` requires the
opposite behaviour from the same guard. Filed as
`decide-does-raise-of-an-existing-object-transfer-ownership` (Track U), with
options, a recommendation, and one seductive shortcut checked and rejected.
Not reverting: that trades this crash for the 1478/1500 leak and turns the other
test red, which is not a return to green.


## The ownership fork is settled, and the blocker moved (frankC, 2026-09-01)

`decide-does-raise-of-an-existing-object-transfer-ownership` is closed for
option (a): FPC 3.2.2 frees a raised object it did not construct (runtime error
216 on the repro; heaptrc shows 2 allocated, 2 freed, 0 unfreed on the
single-raise form), so `raise` transfers ownership unconditionally and
`620989250` adopted the language's rule rather than inventing one. The test is
what must change — phase 3 must allocate per raise instead of re-raising
pre-made objects.

frankB's stated cost for that is gone: the thread-local heap magazine at
`250fdc6bd` makes small alloc/free lock-free per thread under `--threadsafe`,
so allocating per raise no longer serialises on the heap lock, which was the
test's whole reason for reusing objects.

**But the rewrite is blocked, and this ticket's red now has a different cause.**
Attempting it turns up
`bug-a-two-threads-raising-object-exceptions-corrupt-the-heap`: two threads
each raising a freshly constructed object SIGSEGV, with no shared object, no
shared class and no re-raise. Clean at `620989250^`, SIGSEGV at HEAD. Not the
magazine (`-dPXX_NO_HEAP_MAG` crashes identically). Cause: on x86-64 the heap
lock is emitted by codegen at `tkGetMem`/`tkFreeMem` sites and never taken
inside the runtime helpers, so `620989250`'s emitted call to `PXXObjFree`
mutates the free list bare.

blocked-by: bug-a-two-threads-raising-object-exceptions-corrupt-the-heap

The rewrite itself is scoped in the closed decide ticket, including the two
things it must carry (the header sentence stops naming one mechanism, and the
process-wide control has to fail at the SAME N — sensitivity is a hit rate, not
a pass).


## TRIAGE 2026-09-01 (frankC) — this is not a bisect, and the range above is a red herring

`decide-does-raise-of-an-existing-object-transfer-ownership` is SETTLED for
option (a): FPC frees a raised object it did not construct, so `raise` transfers
ownership unconditionally, pxx's behaviour is the language's, and **this test is
what must change.** Nothing below the named sha needs finding.

### What it actually does now

Measured on `compiler/pascal26` at `4a0dd77ef`, sha256 `4907c9f159d9…`,
`--threadsafe`, three runs, deterministic:

The failure is in **phase 1 — the SINGLE-THREADED control** — and the harness
could not show that because the two `WriteLn`s are buffered into a pipe and lost
on the fault. On a pty:

```
start
created
spinraw done hits=100000      <- 100k raises of an INTEGER, clean
                              <- SpinAlpha faults here
```

Cut down to the object loop alone, printing per iteration, it is exact:

```
n=1     iter 1 ok    DONE
n=2     iter 2 ok    DONE
n=3     iter 1, iter 2, then SIGSEGV
n=1000  iter 1, iter 2, then SIGSEGV
```

**It survives two raises of the same object and dies on the third**, with no
thread ever created. So the test's own header — "phase 1 is that
single-threaded control and it runs FIRST… a count from phase 2 means nothing
without a run that cannot produce the failure" — is now describing a control
that itself fails, which makes phase 2's number unreadable rather than merely
absent.

The fault is inside `PXXClassFinalizeManaged` (+119, `mov (%rax),%rax`, walking
a freed link), reached from the handler-exit release. It is NOT `d402a25b2`:
that commit landed 2026-09-01T21:29, hours AFTER the bad sha `e7be39f9a505`
(13:24), and reverting its `ir.inc` hunk and rebuilding still faults 3/3. Checked
rather than argued, because the crash is inside the routine that commit calls.

### Why it stays open and blocked rather than being rewritten now

The rewrite has to make each raise CONSTRUCT its object, since that is what the
settled ownership rule requires. The test's header explains why it was written
not to: "an exception that allocates takes the heap lock on every raise, which
serialises the threads and hides the interleaving under test." So a correct
rewrite either loses the race detector it exists to be, or allocates on two
threads — which is precisely
`bug-a-two-threads-raising-object-exceptions-corrupt-the-heap`. Wired as
`blocked-by` for that reason.

### For whoever picks it up

Do not read the `bad e7be39f9a505 / last good 62e176c3c4e5` range as a lead. It
is real but it dates the OWNERSHIP change's arrival, not a defect. And do not
trust a run whose output is captured through a pipe: this program prints nothing
on the way down, and "no output" reads identically to "crashed at line 1".
