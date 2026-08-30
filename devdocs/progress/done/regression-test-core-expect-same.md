---
prio: 70
track: T
status: done
---

> **Track T by default: no lane could be inferred** from `tools/expect_same.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:tools/expect_same.sh@276 red at 9ced9bbc3e2d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T03:16:01Z
- **Test source:** tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:tools/expect_same.sh@276'` at 9ced9bbc3e2d643dac51501c3324dc972ccdce7e

## Range
> **The named sha `9ced9bbc3e2d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9ced9bbc3e2d`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
pascal26: error: cannot read input file: /tmp/testmgr-scratch-4095178/cnest16/gmain.c
(tail)
pascal26: error: cannot read input file: /tmp/testmgr-scratch-4095178/cnest16/gmain.c

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Root cause and fix — Track T, 2026-08-30

**The lane fallback was right and the name was not.** The job is
`test-core#src:tools/expect_same.sh@276` because `expect_same.sh` is the first
source its recipe mentions — the harness driver, not the subject. The failing
step is line 1 of 13, `./compiler/pascal26 /tmp/cnest16/gmain.c
/tmp/cnest16_26`. (This stub predates
`bug-t-a-job-named-after-its-first-source-file-cannot-name-its-failing-step`
landing an hour earlier; a stub filed now would carry that line in its heading.)

**The defect is in `split_jobs()`, and it is Track T's.** The C include-nesting
test is two adjacent recipe lines:

```make
@python3 -c "...makedirs(d)... writes g0.h..g15.h and gmain.c" $(TESTTMP)/cnest16
./$(COMPILER) $(TESTTMP)/cnest16/gmain.c $(TESTTMP)/cnest16_26
```

`split_jobs` starts a new job at a compile that follows a non-compile line, so
it cuts exactly between them. It then repairs the producer/consumer edges it
just cut, by union-find over shared scratch paths — and that repair keyed on
**exact path equality**. The token sets here are `{/tmp/cnest16}` and
`{/tmp/cnest16/gmain.c, /tmp/cnest16_26}`: **no string in common**, so nothing
merged them and the two jobs had no ordering between them.

**It was a race, which is why it passed for as long as it did.** The producer's
job sorts earlier and is normally dispatched first. On a busy box it stopped
winning. Reproduced in isolation, byte for byte against the log tail above:

```
pascal26: error: cannot read input file: /tmp/testmgr-scratch-4147814/cnest16/gmain.c
```

`split_jobs`' own comment already names this class — *"one producer/consumer
edge is invisible to a filename scan"*, written for the `.so` + bare
`LD_LIBRARY_PATH` case and fixed there with a synthetic token. This is the
second instance of the same class, and the fix has the same shape.

### The fix, and its bound

Every **ancestor directory strictly below `TESTTMP`** becomes a token too.
*Strictly* below is the entire safety argument: `TESTTMP` itself would merge
every job in a target into one, since they all name something under it.

Measured **before** the rule was written, which is what makes it a closed blind
spot rather than a widened net — across `test-core`, `test-threads`,
`lib-test`, `test-nilpy` and `test-asm` there are exactly **three** scratch
paths with a subdirectory component at all (`/tmp/cnest16`, `/tmp/cnest18`, and
one literal `...` in an echo). Result: `test-core` 1599 → **1598** jobs, and no
other target moved by a single job.

**Selector churn is exactly one selector**, and it is this job's own:
`test-core#src:tools/expect_same.sh@276` disappears and **nothing new appears**.
So this cannot produce a wave of false `first-ever run` stubs — the risk that
made renumbering worth measuring rather than assuming.

The merged job runs green (`rc=0`), and with the ancestor tokens removed the
consumer half reproduces the original failure on its own.

**Gate:** `tools/testmgr_split_dir_resource_devtest.py`, 6 guards, 2 negative
controls — removing the ancestor tokens reds 4 (including the real-Makefile
cnest16 case), and changing `>` to `>=` so the walk includes `TESTTMP` reds the
bound guard alone.

*Instrument note:* the bound guard's first fixture merged two chains that were
supposed to stay apart, because a producer line for the second chain sat inside
the first chain's group and chained all three. It merged identically **before**
the fix, which is how it was caught — when a guard fails, the first question is
whether it fails pre-fix too.
- 2026-08-30 — resolved, commit d78ce2f35.
