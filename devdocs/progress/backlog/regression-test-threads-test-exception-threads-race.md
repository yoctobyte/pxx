---
prio: 70
track: A
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
