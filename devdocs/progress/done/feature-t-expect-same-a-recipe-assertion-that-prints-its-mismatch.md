---
slug: feature-t-expect-same-a-recipe-assertion-that-prints-its-mismatch
title: "tools/expect_same.sh — a recipe assertion that prints its mismatch, so job_reason() records the failure instead of the two lines before it"
track: T
type: feature
prio: 45
blocked-by: []
status: done
found: 2026-08-29
found-by: pxx-a5
owner: pxx-a5
---

# `expect_same.sh` — the helper half of the silent-assertion bug

Split out of
[[bug-t-a-silent-test-assertion-makes-the-harness-report-the-wrong-thing]] so it
closes on its own. That ticket has two halves with very different owners:

| half | lane | size |
| --- | --- | --- |
| **the helper** | **T** (`tools/`) | one file — *this ticket* |
| converting 480 cross-target recipe assertions | **A** (`Makefile`) | mechanical, 480 sites |

Landing the helper as step 1 of the parent would leave the parent reading as
in-progress with 480 edits outstanding, which is worse than untouched for
whoever inherits it. As its own ticket it closes, and the parent becomes a clean
Track A dispatch against a helper that already exists and is guarded.

## What it does

```
tools/expect_same.sh <label> <actual> <expected>
```

Exit 0 on equality, printing nothing. On mismatch: a labelled unified diff of
the two operands, exit 1. A recipe line becomes

```make
	tools/expect_same.sh aarch64-fima "$$(tools/run_target.sh aarch64 $(TESTTMP)/x)" "$$($(TESTTMP)/x_x64)"
```

## Four properties that decide whether the reason is USABLE

Getting a diff onto stdout is the easy part. These are the rest, and three of
them came out of getting them wrong first:

**The label is in the output.** `job_reason()` records a tail; the tail has to
say *which* assertion spoke, or the reader is back to guessing from context.

**`-` is expected and `+` is actual.** Transposed sides are their own species of
wasted hour, so a guard pins the direction.

**No absolute `/tmp` path.** testmgr rewrites absolute `/tmp` paths, so a leaked
one makes the text vary by construction. Solved by running `diff` from inside
the temp dir and letting the filenames be the labels — which also sidesteps
`--label`, not portable (busybox spells it `-L`).

**Stable across runs.** `diff -u` stamps each header line with the file's mtime,
so two identical mismatches produced different text — and a reason that changes
every run reads as a *new* failure to anything comparing this run's reds against
the last. The mtime column is trimmed off the two header lines. This one is the
easiest to ship without noticing, because the output looks perfect in isolation.

## The vacuous pass, deliberately not fixed

Two empty operands compare equal, so this passes — and that is exactly how a
test whose subject silently produced nothing looks from the outside. The verdict
is left alone: 480 call sites is the wrong place to change pass/fail semantics.
But it is no longer *silent* — a warning naming the label goes to stderr. A
vacuous pass that announces itself is a lead; one that does not is the shape of
[[feature-t-audit-tests-that-pass-with-the-implementation-removed]].

## A bug found by its own guards, worth recording

The first version chained a portability fallback with `||`:

```sh
diff -u --label ... || diff -u "$tmp/expected" "$tmp/actual" || true
```

`diff` exits **1 when files differ** — the normal path here, not an error — so
the fallback fired on *every* mismatch. The diff printed twice, and the second
copy carried the absolute `/tmp` paths the first had avoided. `||` read as "if
that did not work", when what it means is "if that found no difference".

## Guards

11 in `tools/expect_same_devtest.py`. Four mutations, each fired on exactly the
guards it should: silent on mismatch (5), sides transposed (2), mtime trim
removed (1), vacuous warning removed (1).

Two of those had to be run twice. The first attempt at the mtime mutation was a
`sed` that failed with `unknown option to 's'`, leaving the file unchanged — so
the suite went green and the mutation looked like a guard catching nothing. The
first attempt at the warning mutation cut too much and broke the script, so
seven guards fired on a crash rather than one firing on the change. **A mutation
run only means something once you have confirmed the mutation applied** —
`devtest_report.py`'s recorded lesson, met twice more here.

## What remains, and it is not this ticket

The 480 conversions. Track A's file-lane, mechanical, and per the parent's own
gate must not land concurrently with other A edits to `Makefile`.

## Log
- 2026-08-29 — helper landed with guards; resolved.
