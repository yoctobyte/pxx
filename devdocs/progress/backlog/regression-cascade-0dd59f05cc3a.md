---
prio: 70
---

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 20 jobs newly red in 851f170cb..0dd59f05c (4 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 20 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-06T15:16:57Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `0dd59f05cc3a` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `0dd59f05cc3a`, last good `851f170cb454`, **4 commit(s) in range** (4 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `99c416b54e7b` fix(P): FindSym ranked case-exactness above scope depth, and it is one walk now
- `9075fdcd3e61` fix(P): a class or record const is a constant when named through its type
- `b612f30e8fca` fix(P): a routine-local var array initializer was a missing fork, not a missing capability
- `962cd81e3610` fix(P): a record's static class method is reachable through an instance

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 0dd59f05cc3a5187257914a4b9bfc6676f9378c7

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-aarch64#src:test/test_parallel_for_private.pas`
  - ok: $TMP [code=458520B data=6344B bss=50788B procs=592]
- `test-aarch64#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-aarch64#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000
- `test-arm32#src:test/test_parallel_for_private.pas`
  - ok: $TMP [code=515948B data=6392B bss=50708B procs=623]
- `test-arm32#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-arm32#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000
- `test-c-conformance#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance: 36 pass, 1 fail, 0 skip (of 37) |…
- `test-c-conformance-aarch64#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (…
- `test-c-conformance-arm32#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-arm32: 36 pass, 1 fail, 0 skip (of…
- `test-c-conformance-i386#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-i386: 36 pass, 1 fail, 0 skip (of…
- `test-c-conformance-riscv32#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-riscv32: 36 pass, 1 fail, 0 skip (…
- `test-i386#src:test/test_parallel_for_private.pas`
  - ok: $TMP [code=266092B data=6344B bss=50708B procs=589]
- `test-i386#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-i386#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000
- `test-lua#src:tools/compiler_srchash.sh`
  - @@ -1,4 +0,0 @@ | -HELLO, WORLD 12 Hello | -Hell0, W0rld | -brown,fox,quick,the | -9 8 5 3 2 1 | test-lua: FAILURES
- `test-lua-cross#src:tools/compiler_srchash.sh`
  - @@ -1,4 +0,0 @@ | -HELLO, WORLD 12 Hello | -Hell0, W0rld | -brown,fox,quick,the | -9 8 5 3 2 1 | test-lua-cross: FAILURES
- `test-riscv32#src:test/test_signal_sp_rewrite.pas`
  - Segmentation fault (core dumped) | +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas`
  - Segmentation fault (core dumped) | expect_same: MISMATCH [test_ts_hl_diag26_exit] | --- expected | +++ actual | @@ -1 +1 @@ | -212 | +139
- `test-xtensa#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-xtensa#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*


## TRIAGE 2026-09-06 — frankB. Six rows fixed, TWO causes, and the range was right about one of them

Fixed and pushed: `667934bc5` and `dbe03f106`. Every row below was reproduced
NATIVELY on x86-64 at HEAD, which is the part the job list hid: the cascade
listed only the cross flavours, while tstate had already split the same failures
out as their own native open regressions.

**Cause 1 — five fixtures of OURS that declare one identifier twice.** fpc
refuses all five outright; they were passing only because FindSym used to rank
case-exactness above scope depth (`99c416b54`, in range and correctly named).
Renamed, not worked around.

| fixture | the pair | what it did |
| --- | --- | --- |
| `test_signal_sp_rewrite.pas` | `const SPARE` / `var spare` | `spare[SPARE-1]` became `spare[spare-1]`, so the handler got an SP computed from an array-as-integer and re-faulted until `hits > 3` halted 3 |
| `test_stack_overflow_raise.pas` | same | same |
| `test_parallel_for_private.pas` | `const S = 4000` / local `s: AnsiString` | `for i := 0 to S-1` counted a string pointer: 4378472 iterations |
| `test_critsec_once.pas` | `const K = 50000` / local `k` | `for k := 1 to K` ran zero times |
| `test_threadsafe_heap_lock_deadlock_diag.pas` | `const RING` / `var ring` | the row frankH's `35328fd10` was assumed to have fixed; it had not, it is this |

**Cause 2 — a real compiler bug, and it is NOT in the range.**
`cfloat_global_array_implicit_len_b386.c` returned 3 instead of 42 because
`ParseCProgram` never set `CaseSensitiveMode`: every symbol in a C PROGRAM was
registered case-INsensitively, so a local `int i` answered for a file-scope
`double I[]`. `ParseUsesUnitBody` had always done it for a `.c` pulled through
`uses`. The same hole was in `ParseRustProgram` and `ParseZigProgram`. The
reordering only made a latent defect observable, so bisecting to `99c416b54`
would have named a commit that is not where the fix belongs.

## Still open, and NOT mine

- `test-c-conformance#shard3/6` (`FAIL 00040.c`) on all six flavours: expected to
  clear with the `ParseCProgram` fix, and I cannot verify it -- the c-testsuite
  corpus is not installed in this checkout. **A SKIP, not a green.**
- `test-lua#compiler_srchash.sh` and `test-lua-cross`: the failing step is the
  `$(COMPILER)` dependency, not the lua rows, and the same script was already
  failing in `test-emit-obj` and `test-zlib` rows in earlier reports. The script
  exits 0 here and the lua tree is absent, so this box cannot answer it.
  **UNOWNED.** It needs one.

## What the cascade cost, in one line

Each of the six was diagnosed by `PXXDBG=a.casebind` in one compile -- the
channel prints the exact candidate the old lookup order would have taken -- and
none by bisection. The first run reported ZERO for two of them because they need
`--threadsafe` and the compile dies inside `palthread.pas` before the program
body: a delta instrument is still conditioned on the input reaching the site.
`a.casebind` now prints a `TOTAL seen=/fold=/moved=` denominator so that silence
says which kind of silence it is.
