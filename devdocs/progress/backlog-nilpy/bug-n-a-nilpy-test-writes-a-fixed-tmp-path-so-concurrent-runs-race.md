---
slug: bug-n-a-nilpy-test-writes-a-fixed-tmp-path-so-concurrent-runs-race
title: "A NilPy test writes a fixed /tmp path at runtime, so two concurrent runs on one box race over the same file"
track: N
prio: 45
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-08-28
summary: "MECHANISM, not a file: a test that spells a temp path as a RUNTIME literal cannot be privatized by the Makefile sweep or rewritten by testmgr, so concurrent testmgr runs on one box race over one file -- and this box routinely runs several clones at once. The condition that springs it is any test writing a literal path instead of the env chain TESTMGR_TMP -> TESTTMP -> /tmp. tools/testmgr_hardcoded_tmp_devtest.py is the guard and prints both the offending source and the remedy. THE ORIGINALLY CITED INSTANCE IS FIXED and this summary cited it for 23 days after: test_nilpy_class_named_like_an_rtl_record.npy (introduced f3422cd14) now takes the env chain at line 38 and the guard no longer names it. Recurred instead in TWO new sources, measured 2026-09-20 at 0ae279ae9 by frankz-e5 via `make tools-devtest`: test_nilpy_io_open_in_a_module_that_rebound_open.npy (/tmp/test_nilpy_io_open.txt) and test_nilpy_mmap_read_only_and_struct_unpack_from.npy (/tmp/pxx_test_mmap_read_only.bin). Do not re-cite a firing row here; the recurrence is the point. Filed by Track T; T owns the tool, never the bug."
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
