---
prio: 70
track: A
status: done
owner: frank-optimize
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_opt_store_reload.pas red at c951ec710b33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:52:56Z
- **Test source:** test/test_opt_store_reload.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_opt_store_reload.pas'` at c951ec710b33da734e7141394258135689c3e5fa

## Range
> **The named sha `c951ec710b33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c951ec710b33`, last good `08cbfa20a11d`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
expect_same: MISMATCH [test_opt_sr_O0.4]
--- expected
+++ actual
@@ -15,3 +15,5 @@
 br between
 br after neg
 mem   -112 -112 -110
+reord 635218
+reord2 635317

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 (coordinator) — RETRACKED P → A (O-flavoured), on the diff's own content

Auto-filed as **P** from the test path; the banner in this ticket says the
frontmatter is what the ranker reads, so the guess decides the owner. It is wrong.

The mismatch is two lines the actual output has and the expectation does not:

```
+reord 635218
+reord2 635317
```

Those are emitted by `test/test_opt_store_reload.pas:153` and `:161`
(`WriteLn('reord ', Int64(qh))`). The subject is **store/reload reordering** —
codegen and the `-O` pipeline, i.e. Track **A** under the **O** work-tag, which by
CLAUDE.md is file-owned by A and obeys A's gate. The Pascal frontend is not
involved at any point.

**Read the two candidate causes before fixing**, because they want opposite
changes and the diff alone cannot tell them apart: either the optimizer's
behaviour changed and the new lines are a real regression, or the test grew two
`WriteLn`s and its expectation was never regenerated. **The second one is the
quiet case** — it leaves a permanent red that looks like a codegen bug and wastes
whoever picks it up. Check `git log -- test/test_opt_store_reload.pas` and the
expectation file's mtime first; that is one command and it decides which bug this
is.

Standing, not flaky: STILL-RED on every native report from 06:57Z to 08:45Z. The
attributing sha `c951ec710b33` is a `diag(N)` commit and the earlier one is a
`tstate-ticket` commit — **neither can be the cause**; a tstate red attributes to
the sha it swept.

## 2026-08-30 (coordinator) — BISECTED by Track T: `10c869750675`, which also WROTE this test

`b347147c9`: bad `10c869750675`, last good `08cbfa20a11d`, **1 commit in range** —
so the attribution is exact, not a range.

```
10c869750 07:48 fix(O): -O3 store->reload elimination elided a load the emitter had reordered
```

**That commit added 45 lines to `test/test_opt_store_reload.pas` itself**, and the
entire mismatch is the two `WriteLn`s it added at `:153`/`:161`:

```
+reord 635218
+reord2 635317
```

So the two candidate causes I wrote above are now **one commit apart**, and both
are still live because the bisect cannot separate them — the same commit changed
the optimizer AND grew the test:

- **the expectation was never regenerated** — a test-authoring miss, no compiler
  defect, fix by regenerating; or
- **the two new `WriteLn`s expose a real difference** between the levels
  `expect_same.sh` compares (the failing label is `test_opt_sr_O0.4`), in which
  case the commit's own fix is incomplete and the test is doing its job.

**Do not assume the first because it is cheaper.** `tools/expect_same.sh` is a
generic three-argument assert (`<label> <actual> <expected>`), so *what* is being
compared lives in the Makefile recipe, not in the script — read that recipe first.
If the two operands are the same program at two `-O` levels, then a difference is
a codegen finding and regenerating the expectation would **delete the detector**
(face 195). If the expectation is a recorded file, regeneration is correct.

**One commit, one test, one recipe — this is a ten-minute triage and it has been
red since 07:48.**

## 2026-08-30 (frank-optimize) — RESOLVED: candidate 1. The golden was committed short, in the SECOND of two copies.

Measured before touching anything, because the three candidate stories wanted
opposite fixes. Built at `780ec9f7c` (`converged after 1 round(s)`, sha256
`6319b892f517`), then ran the subject directly:

```
$ ./compiler/pascal26     test/test_opt_store_reload.pas /tmp/.../sr_O0
$ ./compiler/pascal26 -O3 test/test_opt_store_reload.pas /tmp/.../sr_O3
$ diff <(sr_O0) <(sr_O3)      -> identical, 19 lines, ending
                                 reord  635218
                                 reord2 635317
```

So:

- **Not candidate 2** (a non-reproducible value). `635218` / `635317` are the
  constants the test's own section-6 comment documents as FPC 3.2.2's answers,
  and `222` is the failure value. They are not addresses. The `-O3` arm agrees
  with `-O0` exactly, which is the whole differential the test exists to assert.
- **Not candidate 3** (a fleet-vs-author codegen difference). The two extra lines
  are missing from the EXPECTATION, not extra in the output, so every host fails
  identically — which is why plexus and seven both went red rather than one of
  them.
- **Candidate 1, with a structural cause worth more than the fix.**

### The mechanism

`test/test_opt_store_reload.pas` is registered **twice**, in two targets, with its
expectation written out verbatim in each:

| target | opens | expect rows | golden |
| --- | ---: | --- | --- |
| `test-nilpy` | 368 | `test_opt_sr_O0.1` / `.2` @ 851 | 19 lines, **current** |
| `test-core` | 4502 | `test_opt_sr_O0.3` / `.4` @ 11215 | 17 lines, **stale** |

`10c869750` — the commit Track T bisected to, and correctly so — added section 6
to the test and updated the copy at line 851. The copy 10,364 lines away kept the
17-line golden. Nothing in the Makefile hints the second copy exists, and the
half that goes red is `test-core`, which the per-fix loop does not run; so it was
silent at edit time and red in a sweep several hours later.

The label suffixes are the tell and the trap at once: `.1`/`.2` vs `.3`/`.4` look
like a copy index and are not — they are per-target sequence numbers, which is
also why the existing `.npy` guard keys on the source rather than the label.

### The fix

Brought `test-core`'s block into sync with `test-nilpy`'s — not just the two
missing golden lines. `10c869750` had made **three** changes to the block and the
second copy had missed all three:

1. the golden's `reord 635218` / `reord2 635317` rows — the red;
2. the eight-line comment explaining why those rows assert the VALUE and never
   "the two `-O` levels agree" (they agreed at 222 too);
3. the `a.reload DECLINED` assertion — the emit-time refusal that is the actual
   subject of `10c869750`'s fix. **`test-core` was asserting the marks fired and
   not that the refusal did**, i.e. the half of the guard that catches a
   regression of this exact bug was absent from one of the two targets.

Point 3 is why syncing the whole block beat patching two `printf` lines: the
minimal fix would have left `test-core` green while blind to the miscompile.

### Verification

Every row of the repaired `test-core` block, run by hand against the
`6319b892f517` binary (the ticket's `testmgr --tier native` repro is refused by
`.claude/hooks/no-full-suite.sh`, which allows only `--tier quick`; the rows
themselves are the assertion and need no harness):

```
expect_same test_opt_sr_O0.3  (-O0 vs -O3)                  PASS
expect_same test_opt_sr_O0.4  (-O0 vs the 19-line golden)   PASS
a.reload marked   >= 6    -> 250   PASS
  ... ' bo' >= 1, ' c' >= 5        PASS
a.reload DECLINED >= 1    -> 4     PASS
make -n test-core / test-nilpy     exit 0 (recipe still parses)
```

No compiler source was touched: `compiler/ir_codegen.inc` and `compiler/defs.inc`
were read and left alone. The fix is one Makefile block.

### Filed, not fixed here

`bug-t-the-duplicate-expectation-ratchet-is-npy-only-and-the-first-escape-was-a-pas-test`
[T, p55]. `tools/npy_cross_target_expectation_devtest.py` — landed the same day,
for precisely this hazard — filters its population to `s.endswith(".npy")` while
its own `COMPILE_RE` already matches `.pas` and `.c`. This regression is a `.pas`
test in the same duplicated block the guard was written about; one predicate
stood between the ratchet and catching it before the push. The ticket carries the
measurement showing why the naive widening is wrong (144 false findings) and the
137-source / 15-exception key that works. Track T owns that file, so it is filed,
not edited.
- 2026-08-30 — resolved, commit 6922255a6.
