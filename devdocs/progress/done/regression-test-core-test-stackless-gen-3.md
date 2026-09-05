---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_stackless_gen26`, which names `test/test_stackless_gen.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_stackless_gen.pas at f2c6ff3288b4 in step 1/2, `./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_stackless_gen26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T18:04:59Z
- **Test source:** test/test_stackless_gen.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_stackless_gen.pas`.
  ```
  ./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_stackless_gen26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_stackless_gen.pas'` at f2c6ff3288b407ca08ee7e469f4b2a8b56f98972

## Range
> **The named sha `f2c6ff3288b4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f2c6ff3288b4`, last good `7867c5481c01`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:107: error: incompatible types: cannot assign Int64 to Pointer
(tail)
pascal26:107: error: incompatible types: cannot assign Int64 to Pointer

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a058097b7.

## Closed 2026-09-05 (frankB) — reproduce-clean at HEAD, full job, not just the failing step

Ran the ticket's own Repro line — `testmgr.py --tier native --job ...` — at HEAD,
not the sha it was filed against: **1/1 pass, testmgr GREEN.** The failing step
alone was also re-run and compiles. Both, because a ticket whose recorded
failure is step 1 of 2 can have step 2 fail for its own reasons, and "the
failing step passes" is a narrower claim than "the job passes".

**CAUSE — CORRECTED, AND MY FIRST ATTRIBUTION WAS WRONG.** I recorded these as
extra instances of `4760474da` (my pointer-sink rule) fixed by the revert
`2d6bfadd6`. **That is not the cause.** frankD measured the real one from the
watcher's log tails: the four bare `test_c_gtk*` rows all logged
`pascal26:2: error: uses: unit source not found: gtk`, and `gtk3_stock` logged
`C include file not found: "gtk/gtk.h"` naming the directory it searched.
**Seven has no GTK development headers installed at all** — not a version
mismatch, not a code defect, and not Track P.

**AND MY GREEN COULD NOT HAVE DISCRIMINATED.** I ran these on plexus, which has
BOTH `/usr/include/gtk-2.0/gtk/gtk.h` and `/usr/include/gtk-3.0/gtk/gtk.h`.
A host with the headers passes whether or not any compiler bug exists, so
"1/1 pass, GREEN at HEAD" is a true statement about **plexus** and says nothing
about the failure, which happened on **seven**. That is this repo's own
"nothing observably differs is a claim about ONE target" hazard, in the one
variable I did not think to check — not a target architecture this time, but the
build host's installed packages. The tests being green here is exactly what a
missing-header failure over there looks like from this side.

**What survives, and what does not.** The rows do pass on plexus at HEAD — that
measurement is real, and it does rule out a tree-wide code defect reachable
here. What it does not do is close these tickets, because the condition that
produced them is still true on the host that produced them. **Disposition is
frankD's**, who found the cause and holds the evidence; this section exists so
that nobody reads my original attribution and believes it.

*(A trap frankD paid for and recorded: the "Failing step" line quoted in these
tickets is TRUNCATED. The real recipe for `gtk3_stock` is
`./$(COMPILER) -Futest/gtk3stock -I/usr/include/gtk-3.0/ test/...`; running the
ticket's shorter command hits a deliberate `#error` about GTK2-vs-GTK3 that
looks like a shared-cause smoking gun and is an artefact of the missing flags.
Go to the Makefile recipe. The four bare rows happen to match, which is what
makes the fifth easy to get wrong.)*

**The lane was a guess and the guess is now moot.** The banner at the top of
this file says so itself: `track: P` was inferred from the failing step naming a
`.pas` file, and the ranker reads only the frontmatter. That put six auto-filed
regressions in the top rows of `ready --track P`. They are closed on evidence,
not re-laned — a re-lane would have moved a finished ticket to another queue.
