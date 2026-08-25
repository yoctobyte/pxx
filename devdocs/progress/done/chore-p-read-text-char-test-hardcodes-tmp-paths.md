---
track: P
prio: 50
type: chore
summary: "test/test_read_text_char.pas (00d1105d5) hardcodes /tmp/test_read_text_char_{a,b}.txt, written by the test binary at runtime where no Makefile sweep or testmgr privatization reaches them. The ratchet guard tools/testmgr_hardcoded_tmp_devtest.py is RED on master because of it, so `make tools-devtest` fails at that step for every lane."
status: done
owner: claude-A
---

# `test_read_text_char.pas` hardcodes two /tmp paths — the ratchet is red

- **Type:** chore — **Track P** (owns the test source). Filed by Track T,
  which owns the guard but never the bug.
- **Instance of** [[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]]
  (the 60-path umbrella, prio 45). This one is filed separately because it is
  not backlog: it turns a guard RED **today**.

## What happens

```
$ make tools-devtest
FAIL: new hardcoded /tmp path(s) in compiled test sources...
  test/test_read_text_char.pas       /tmp/test_read_text_char_a.txt
  test/test_read_text_char.pas       /tmp/test_read_text_char_b.txt
make: *** [Makefile:11422: tools-devtest] Error 1
```

`tools/testmgr_hardcoded_tmp_devtest.py` is a **ratchet**: it carries a `KNOWN`
baseline of the 60 pre-existing paths and fails on anything new. Landed
2026-08-20 in `00d1105d5` ("feat(P): read(f, c) into a Char, through the RTL's
TextReadChar"), the test added two paths that were not in the baseline, so the
guard does exactly what it was built to do — and `make tools-devtest` now aborts
at that step, before the ~25 guards that sort after it.

## Why it matters beyond the red

The path is written by the **compiled binary** at runtime. The Makefile
`$(TESTTMP)` sweep only reaches paths the *recipe* names, and testmgr privatizes
the recipe text it executes, not string constants inside a binary it runs. So
two concurrent runs — a dev gate and the watcher on the same box — share
`/tmp/test_read_text_char_a.txt` and can read each other's bytes. The test is
also read-back-what-I-wrote, which is exactly the shape that produces a
plausible wrong value rather than a crash.

## The fix (one of two, Track P's call)

1. **Preferred:** read the directory from the environment — `TESTTMP`, which the
   sweep already exports, defaulting to `/tmp` so an unset environment stays
   byte-identical. Then delete nothing from the guard; the paths simply stop
   being literals.
2. **If the name must be fixed** (it must not — nothing in the recipe names
   these files), add both to `ALLOWED_PATHS` in the guard *with a reason*.

Do not add them to `KNOWN`: that list is the frozen pre-ratchet baseline, and
growing it is how the ratchet stops ratcheting.

## Gate

`make tools-devtest` green (Track T's guard passes), plus the test itself still
passes in the quick tier.

# Already fixed — verified 2026-08-25

Landed in `b7d26e906` ("test(P): test_read_text_char writes into $TESTTMP, not a
shared /tmp name"), which took option 1 exactly as this ticket recommended: the
test reads `TESTTMP` from the environment and defaults to `/tmp`, so the two
paths stopped being literals and nothing had to be added to the guard's
allow-list.

Re-verified today rather than assumed — `python3
tools/testmgr_hardcoded_tmp_devtest.py` prints
`ok   no unlisted hardcoded /tmp path (61 known, 1 allowed file(s), 2 allowed
path(s))` and exits 0.

The umbrella [[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]] (the 60
baselined paths) is unaffected and stays open.

## Log
- 2026-08-25 — resolved, commit dd35abca2.
