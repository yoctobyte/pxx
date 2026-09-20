---
slug: bug-n-a-nilpy-test-writes-a-fixed-tmp-path-so-concurrent-runs-race
title: "A NilPy test writes a fixed /tmp path at runtime, so two concurrent runs on one box race over the same file"
track: N
prio: 45
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-28
summary: "MECHANISM, not a file: a test that spells a temp path as a RUNTIME literal cannot be privatized by the Makefile sweep or rewritten by testmgr, so concurrent testmgr runs on one box race over one file -- and this box routinely runs several clones at once. The condition that springs it is any test writing a literal path instead of the env chain TESTMGR_TMP -> TESTTMP -> /tmp. tools/testmgr_hardcoded_tmp_devtest.py is the guard and prints both the offending source and the remedy. THE ORIGINALLY CITED INSTANCE IS FIXED and this summary cited it for 23 days after: test_nilpy_class_named_like_an_rtl_record.npy (introduced f3422cd14) now takes the env chain at line 38 and the guard no longer names it. FIXED 2026-09-20 in 35841d247, and the recurrence was THREE sources, not the two measured on 09-20 -- the third is test/lib_findfirst.pas, a .pas, and WHY IT WAS MISSED IS UNKNOWN -- two explanations were offered and both are withdrawn as unmeasured. Mine (a reading filtered by file extension) was never measured. The truncation one (`make tools-devtest` pipes each failing guard through `tail -25`, Makefile:39296, while the guard printed findings FIRST and 22 lines of remedy AFTER) was REFUTED BY REPLAY at 383a817a4: the 0ae279ae9 guard and all three offending sources restored and re-run give 27 lines, tail -25 drops the blank and the FAIL HEADER, and all three findings survive; rows start going at FOUR. The `exactly 25 lines` tell is unfalsifiable besides -- the block is exactly 25 whenever this guard fails at all, at one finding or thirty. The ORDERING fix landed anyway on its own merits (383a817a4): findings last, ending on a line carrying their count. Read a member guard's findings by running it directly, never out of the aggregate's log. The env chain ORDER is the part this ticket's own body got wrong -- TESTMGR_TMP must come FIRST, because testmgr launches a job through an allowlist (PXX_ TESTMGR_ LC_ QEMU_) that TESTTMP does not match, so the remedy the body prescribes would pass a presence check and still race. The GUARD already enforces that order and has since bug-t-the-hardcoded-tmp-guard-recommends-a-variable-testmgr-strips (done); a same-day note here claiming otherwise is corrected in the body. tools-devtest now prints 165 guard(s) green, zero red. Do not re-cite a firing row here; the recurrence is the point. Filed by Track T; T owns the tool, never the bug."
---

# What is wrong

`test/test_nilpy_class_named_like_an_rtl_record.npy` writes, re-reads and then
deletes a probe file at a **fixed absolute path**:

```
line 51:  f = open("/tmp/pxx_nilpy_rtlrec_probe.txt", "w")
line 56:  g = open("/tmp/pxx_nilpy_rtlrec_probe.txt", "r")
line 63:  os.remove("/tmp/pxx_nilpy_rtlrec_probe.txt")
```

The path is chosen **at runtime, by the compiled program**. That is what makes
it different from a fixed path in a Makefile recipe: the Makefile sweep never
sees it, and testmgr's per-run privatization has nothing to rewrite. Every run
of this test on a box, from any clone, uses the identical file.

# Why it matters here specifically

This is not a theoretical race. Several clones' testmgr run concurrently on
plexus as a matter of course — an `opt` sweep this session recorded
`NOTE this run shared the box with another clone's testmgr` and named two other
clones. With two runs overlapping:

- run A writes the probe; run B truncates it with its own `open(..., "w")`;
- run A reads back B's content, or reads a half-written file;
- whichever finishes first calls `os.remove()`, and the other's read or its own
  cleanup then fails on a file that is already gone.

The failure is **intermittent and blames the wrong thing**: it surfaces as a
NilPy class/RTL-record assertion failing, not as a file-sharing problem, and it
only appears when the box is busy. That is the expensive shape — a flaky red
whose message points away from its cause.

# How the guard found it

`tools/testmgr_hardcoded_tmp_devtest.py` exists for exactly this class and is
**RED on master today**:

> FAIL: new hardcoded /tmp path(s) in compiled test sources. These are written
> at RUNTIME, so no Makefile sweep reaches them and testmgr cannot privatize
> them — two concurrent runs share the file.

It is one of the 89 guards in `tools-devtest`, so the job is red for this alone
(88 green, 1 red).

# The fix

The devtest states both accepted forms:

- **Read the directory from the environment** — `$TESTTMP`, which the sweep
  already exports, defaulting to `/tmp` so the behaviour stays byte-identical
  when it is unset. This is the wanted fix.
- Or add the path to `ALLOWED_PATHS` **with a reason**, if this test genuinely
  needs a shared fixed name (it does not appear to — the file is a private
  round-trip probe created and deleted within the one test).

No sibling `.npy` test currently reads `TESTTMP`, so whoever takes this sets
the pattern for the rest of the NilPy suite.

# Boundaries

- **Filed by Track T, to be fixed by Track N.** The tool that caught it is T's;
  the test file is the NilPy suite's, and T does not fix another lane's bug.
- Introduced by `f3422cd14` ("fix(nilpy): a main-program class must not be
  visible inside a unit"). The commit's actual subject is fine — this is the
  probe it added to observe the behaviour, not the fix itself.
- **`tools-devtest` stays red until this lands**, so a real regression in any of
  T's other 88 guards is currently hiding behind a known red. That is the reason
  for p45 rather than lower: a red gate that everyone knows about stops being
  read.

## 2026-09-20 — the cited instance was fixed; the mechanism recurred twice (frankz-e5)

**The summary above was rewritten today and this note records why, because the
failure is one CLAUDE.md names and this is a dated instance of it.**

`test_nilpy_class_named_like_an_rtl_record.npy:38` now reads
`... or "/tmp") + "/pxx_nilpy_rtlrec_probe.txt"` — the env chain, correctly. It
was fixed at some point after 2026-08-28 and **the summary went on naming it as
the live offender**, so a seat dispatched to this p45 would have opened a
correct file and reasonably concluded the ticket was done.

**Measured 2026-09-20 at `0ae279ae9`,** `make tools-devtest`, job's own verdict
`163 green, 2 RED` over 165 of the 166 files `tools/*devtest*.py` globs:

    test/test_nilpy_io_open_in_a_module_that_rebound_open.npy   /tmp/test_nilpy_io_open.txt
    test/test_nilpy_mmap_read_only_and_struct_unpack_from.npy   /tmp/pxx_test_mmap_read_only.bin

**Why nobody noticed for 23 days, and it is not inattention.** This guard
reports through `tools-devtest`, which is an AGGREGATE reporting under the
opaque shard `tools-devtest#00`. That job has been continuously red since
**2026-09-12** (`new_red` at `e115014ceb5e`, then **182 consecutive `still_red`**
through 09-20, **zero transitions**). **A saturated aggregate cannot report a new
red inside it** — so this recurrence, an unwired-test omission on 09-14 and a
binary-name collision on 09-16 all landed into one unchanging level. Written up
in `devdocs/dev/debugging-playbook.md`, "AN AGGREGATE JOB SATURATES".

**The remedy the guard itself prints** is the env chain, in Pascal, C and NilPy
spellings. Nothing here needs designing.

## 2026-09-20 — fixed, and the remedy this ticket prescribed was HALF WRONG (frankS)

`35841d247`. `tools/testmgr_hardcoded_tmp_devtest.py` rc=1 -> rc=0, and
`make tools-devtest` now prints its own verdict as **`165 guard(s) green`** —
no red, so the saturation this ticket predicted and priced is over.

**THREE files, not the two measured on 09-20.** The third is not a `.npy` and
that is why two censuses in a row missed it:

    test/test_nilpy_io_open_in_a_module_that_rebound_open.npy   /tmp/test_nilpy_io_open.txt
    test/test_nilpy_mmap_read_only_and_struct_unpack_from.npy   /tmp/pxx_test_mmap_read_only.bin
    test/lib_findfirst.pas                                      /tmp/pxx_lib_findfirst_sandbox

The guard globs compiled test SOURCES, which is every frontend; the readers
kept summarising it as a NilPy problem because the first instance and the
recurrence both happened to be `.npy`. The mechanism is frontend-neutral.

**THE ENV CHAIN IN "The fix" ABOVE IS THE DEFECT WEARING A FIX.** That section
says to read `$TESTTMP`, *"which the sweep already exports"*. It does, to a
`make` recipe — and **not to a testmgr job**, which is the run that actually
races. testmgr launches jobs through an env allowlist
(`ENV_ALLOW` / `ENV_ALLOW_PREFIXES` = `PXX_ TESTMGR_ LC_ QEMU_`), and
`TESTTMP` matches no prefix in it. A test that consults `TESTTMP` alone gets
nothing under testmgr and falls through to `/tmp` — passing this guard, in the
wanted form, **still racing**. The order must be

    TESTMGR_TMP  ->  TESTTMP  ->  /tmp

with `TESTMGR_TMP` FIRST because it is the only one that survives into a job.
All three files now take it in that order.

**Positive control that the env arm is READ and not merely present**, since a
chain whose first two arms are dead is indistinguishable from a correct one on
a box where `/tmp` happens to be free: `TESTMGR_TMP=/nonexistent-franks-probe`
gives `PRECONDITION FAILED: no sandbox at /nonexistent-franks-probe/pxx_lib_findfirst_sandbox`
and `total ok 0 / 1`. With the env unset, 44/44; with an explicit argument,
44/44; both `.npy` MATCH their `.expected`.

**What should retire the guard, not just this ticket:** the guard cannot see a
test that reads `TESTTMP` only, because that IS its prescribed remedy. A test
written to the letter of the advice above passes and still races under
testmgr. Teaching it to require `TESTMGR_TMP` first is a Track T change and is
not filed — say so before quoting a green from it.

## Log
- 2026-09-20 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 778d63ad3.

## 2026-09-20 — CORRECTION, same day, same seat: the gap I just described is CLOSED, and I said so while holding the file that closes it (frankS)

The note above ends *"Teaching it to require `TESTMGR_TMP` first is a Track T
change and is not filed."* **Both halves are false.**

It is BUILT. `tools/testmgr_hardcoded_tmp_devtest.py` carries a SECOND check —
`ENV_READ_RE`, `KNOWN_ENV_ONLY` — whose header block states the allowlist
argument in the same terms I wrote it in, and it enforces the ORDER, not merely
the presence. Positive control, run before writing this: a scratch Pascal file
under `test/` reading `GetEnvironmentVariable('TESTTMP')` with no
`TESTMGR_TMP` arm makes it exit **1** and name the file; removing the file
returns it to **0**. Five files are grandfathered in `KNOWN_ENV_ONLY` with
their owning lane named, so it is a ratchet exactly like `KNOWN`.

And it is FILED, and closed:
`devdocs/progress/done/bug-t-the-hardcoded-tmp-guard-recommends-a-variable-testmgr-strips.md`,
cited by name in the guard's own comment block four lines above the regex.

**What produced the error is worth more than the error.** I derived the
allowlist fact correctly, from `testmgr`, and then narrated it as a discovery
instead of grepping for whoever had it first — **within an hour of telling
frankz-e5 that the lesson from their own correction was to grep for whoever
already called the hazard, and to attach evidence to their ticket rather than
write a new page.** Same failure, one layer in, in the text arguing for the
remedy. The tell was available and I read past it: the guard PRINTS the ordered
chain with the allowlist reasoning attached, and I quoted that output in this
session while calling the check absent.

So the sentence to distrust is not the measurement — the measurement was
right — it is **"and nobody has built this"**, a quantifier over a population I
never enumerated, arriving at the end of a paragraph whose earlier clauses were
all verified. CLAUDE.md names exactly this ("THE CLAUSE TO GO MEASURE IS THE
QUANTIFIER"); the checked half lent its credibility to the unchecked half.
