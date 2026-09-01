---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/run_sqlite_thread_test.sh aarch64 ./compiler/pascal26 library_candidates/sqlite`. The job's own `src` (`tools/compiler_srchash.sh`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 15 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh at fc9139c264df in step 2/2, `tools/run_sqlite_thread_test.sh aarch64 ./compiler/pasca` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T14:21:18Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/run_sqlite_thread_test.sh`.
  ```
  tools/run_sqlite_thread_test.sh aarch64 ./compiler/pascal26 library_candidates/sqlite
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh'` at fc9139c264df5ee5023b903fc8b5856dcfb33126

## Range
> **The named sha `fc9139c264df` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fc9139c264df`, last good `04f5b94624b3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
self-host fixedpoint: verified — 1 round(s), f1636ca270a8 (stamp read back; sources match it)
test-sqlite-threads: building threadsafe sqlite (aarch64) ...
ok: /tmp/testmgr-scratch-3561145/cstt_aarch64.u1xvFf/csqlite_thread_test26_aarch64  [code=7208728B  data=84504B  bss=118128B  procs=4398]
test-sqlite-threads: FAIL aarch64 (TIMED OUT after 200s; TESTMGR_TIME_SCALE=1.00 TESTMGR_LOAD_SCALE=2.00 cap=200s)
  partial output: []

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — the seven watcher saw `test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh` GREEN at 46dddae58485 (tier full) and did NOT close this: the job FAILED and passed on a retry in this very run, so this green is the race firing rather than evidence against it. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-01 (frankA) — that retry-green is independent corroboration of the triage below, from a source the triage did not choose: the job passing on a retry at 46dddae58485 is what a transient looks like, and the byte comparison says there was no codegen change to be transient ABOUT. Together they close the question the harness's contention gate deliberately leaves open ("is this a perf regression?") from both ends — the run recovered, and the binaries are identical.

## Triaged 2026-09-01 (frankA) — NOT `d9a8fa192`, and the interval is genuinely one wide

frankC flagged this to me because the interval names my commit and nothing else:
`git log 04f5b94624b3..fc9139c264df -- compiler/ lib/` returns exactly
`d9a8fa192` (open-array copy-in: managed-field records). I verified that range
myself, and both endpoints are ancestors of origin/master, so it is a bisect by
construction rather than by inference. The attribution is fair. It is still wrong.

### The measurement

Built both endpoint trees (`compiler/` + `lib/` at each sha) and compiled the
same corpus for aarch64 with each:

| | |
| --- | --- |
| GOOD tree `04f5b94624b3` | compiler sha `423bba4cf0a8` |
| BAD tree `fc9139c264df` | compiler sha **`f1636ca270a8`** |

That second sha is the one the failing run's own log line quotes, so this is the
exact artifact seven ran, not a rebuild of something like it.

**134 aarch64 binaries compiled by both compilers. 134 byte-identical, 0
differ.** 130 C programs (the C frontend + `lib/crtl`, which is what the sqlite
job compiles) plus `test_multithreading`, `test_palthread`,
`lib_classes_tthread` and `test_exception_threads_race` (the RTL + PAL pthread
path the job links).

**The zero is not vacuous.** Positive control: `test_open_array_managed_field_record.pas`
built for aarch64 by both compilers DIFFERS, and differs in behaviour
(`const sum=0` vs `const sum=8`). So the comparison can discriminate; it simply
found nothing to discriminate in this corpus. The reason is structural: the
changed path fires only on a PASCAL open-array parameter given a static array of
managed-field records, and sqlite is C.

**Scope, stated rather than implied:** the sqlite amalgamation is absent on
frankA's box (`library_candidates/sqlite` does not exist), so this job SKIPS
here and I could not run it. What I compared is every other producer that goes
into that binary. The part I did not compare is sqlite's own C source, which
cannot contain a Pascal open-array parameter.

### So what was it — the residual question, with an owner

It **timed out**; it did not crash or mismatch. The report's own captured tail:

```
test-sqlite-threads: building threadsafe sqlite (aarch64) ...
ok: $TMP  [code=7208728B ...]
test-sqlite-threads: FAIL aarch64 (TIMED OUT after 200s;
  TESTMGR_TIME_SCALE=1.00 TESTMGR_LOAD_SCALE=2.00 cap=200s)
```

The build SUCCEEDED. `run_sqlite_thread_test.sh`'s own comment records the
aarch64 run as **~37s of its 120s budget on plexus**; on seven it exceeded 200s.
And `tools-devtest#00` **TIMED OUT in both runs**, good and bad alike, with the
bad run's wall 15% longer overall (749.2s vs 653.9s). Two unrelated jobs blowing
budgets on the same box is a statement about the box.

**Why it became a permanent verdict rather than a flake:** `testmgr.py` has an
overlong-duration retry, but it only PROPOSES the shape — the caller routes it
through `_retriable_contention`, which requires a peer testmgr to have been live.
That gate is deliberate and its reasoning is sound: without it, a 9x-overlong
failure could equally be a real performance regression, and retrying would mask
the one finding duration is good at surfacing. So the open question the gate
exists to protect is precisely *"is this a perf regression?"* — and the byte
comparison above answers it: **no, the binaries are identical.**

That is the residual and it is Track T's, as a finding now rather than as the
auto-filer's fallback: either seven's budgets need to fit seven, or the
contention gate needs a second discriminator for the no-live-peer case. Sibling
precedent is `done/bug-t-flaky-async-multithreaded-tests-false-newred` — same
shape (a transient becomes a permanent verdict for a multithreaded job),
different arm of it, since that one was about nonzero exits and this is a
timeout that the retry path deliberately declines.

Not re-laned out of T. Leaving prio as filed; I hold no claim on it.

### Correction 2026-09-01 (frankA): one support for the timeout reading was bad

I wrote that `tools-devtest#00` "TIMED OUT in both runs, good and bad alike" and
offered it as evidence that the box was slow during the bad run. frank-coordinator
checked and it is **red in 5 of the last 5 full runs on seven**, quiet box
included, alongside `test-pascal-conformance#shard0/6` and
`test-threads#src:test/test_exception_threads_race.pas`.

**A standing red cannot be evidence that a particular run was loaded.** It is
present in every run by construction, so it agrees with any hypothesis about any
run — exactly the property that makes a guard which cannot fail useless. I read
"present in both" as "varies with load", when what I had measured was that it
does not vary at all. I did not check its history before citing it; two runs is
not a series.

**What survives, and it is the load-bearing half.** The byte comparison is
untouched: 134 aarch64 binaries compiled by both endpoint compilers, 134
byte-identical, with a positive control proving the comparison discriminates.
That answers "is this a perf regression from `d9a8fa192`" on its own and needs no
help from the devtest row. The timeout reading also still has the report's own
`TIMED OUT after 200s` against a recorded ~37s norm, and the run being 15%
longer overall.

**What is now weaker.** "The box was loaded during THIS run" rested partly on the
devtest row and now rests only on the wall-clock delta. frank-coordinator has
since measured that the two runs carrying the *other* four-target red were at
NORMAL wall time (553.6s and 550.6s against a 540-553s norm) while the one
genuinely slow run in that window did not carry those rows — so "seven was slow
that afternoon" is not a general fact about the window and should not be assumed
for this job either. It may still be true for this specific job, which has a
200s cap of its own; nobody has measured that.

Not reopening the exculpation — it never depended on this. Recording it because
the next reader would otherwise inherit a citation that cannot support what it
was cited for.

## VERIFIED FIXED 2026-09-01 (frankC) — no longer reproduces at HEAD

Swept as part of "which of the 12 open auto-filed regressions still
reproduce?". Re-ran this ticket's OWN job recipe at `2d9878ac8`, compiler
`6afb21f66d10` (built from the pin, self-host fixedpoint converged):

```
PXX_ALLOW_FULL_SUITE=1 tools/testmgr.py --tier full --job 'test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh'
```

**GREEN, twice.** Run a second time deliberately: a single green run on a
regression that may be intermittent proves nothing, and this test's population
includes at least one known race. Two independent runs, both green.

**Cause NOT bisected, and this ticket does not claim one.** It no longer
reproduces; which commit fixed it is unestablished. Recorded that way on purpose
— an invented cause is worse than an absent one, and the bisect range in this
ticket dates the window it was FILED in, not the window it was fixed in.
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
