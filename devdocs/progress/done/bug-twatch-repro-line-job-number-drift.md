---
prio: 55
---

# bug: twatch repro lines rot — job numbers drift as tests are added

- **Type:** bug (Track T, testmgr/twatch)
- **Found:** 2026-07-12, while triaging regression-test-core-665/666/676

## Problem

Auto-filed regression tickets carry a repro line like

```
tools/testmgr.py --tier native --job 'test-core#665'
```

but `test-core#NNN` is a positional index into the target's Makefile recipe
lines. Adding a test anywhere earlier in `test-core` renumbers everything after
it. The three gtk tickets above were filed against #665/#666/#676; by the time
they were triaged (same day) those tests were #681/#682/#683, so every repro
line in the ticket ran the *wrong test*.

Same drift breaks tstate history: "test-core#665 red" from two weeks ago is not
the same job as today's #665, so FIXED/NEW-RED transitions across a renumbering
are meaningless.

## Why it survives today

The `- **Test source:**` line twatch already records (`test/test_c_gtk_window.pas`)
is what actually identifies the job — triage works by grepping `--list` for the
source file. So the useful key exists; the repro line just doesn't use it.

## Fix sketch

Make the job identity source-derived rather than positional. Cheapest version
that fixes both symptoms:

- give `--job` a source-file form (e.g. `--job src:test/test_c_gtk_window.pas`,
  matching any job whose `src` contains that path), and emit *that* in the
  ticket repro line and in tstate rows;
- keep `target#NN` as a display label only.

Alternative (bigger): hash the recipe lines into a stable job id. Overkill —
the source path is already unique for the unit-test jobs, and jobs with no src
(corpus, emit-obj) are few and rarely renumber.

## Gate

`tools/testmgr.py --tier full` green; a filed ticket's repro line must still
select the right job after a test is inserted above it.

## Log
- 2026-07-12 — resolved, commit 6ec9cefb.
