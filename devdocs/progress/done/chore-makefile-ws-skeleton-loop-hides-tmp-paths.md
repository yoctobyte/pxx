---
track: A
prio: 40
type: chore
summary: "The whitespace/fortran/algol skeleton loop in Makefile:5313 reaches /tmp through a shell variable, so split_jobs cannot merge the recipe and testmgr cannot privatize the path. tools/testmgr_tmp_var_devtest.py is RED on dev because of it, which stops `make tools-devtest` before the ~20 guards that sort after it."
status: done
owner: trackA-worker
---

# The skeleton-language loop hides its /tmp paths in a shell variable

- **Type:** chore — filed by **Track T**, which owns the guard but never the
  bug. Ownership follows the Makefile recipe (`432ad1405`, the Whitespace
  frontend skeleton, plus the fortran/algol siblings it loops over).

## What happens

`tools/testmgr_tmp_var_devtest.py` fails: the recipe for
`test-core#src:test/test_ws_skeleton.ws` reaches `/tmp` through the loop
variable `$$t` rather than naming it. Because `tools-devtest` stops at the first
failure, every devtest sorting after it goes unrun.

## Why the guard cares

testmgr privatizes `/tmp` paths by rewriting the **recipe text** it executes, so
two concurrent runs — a dev gate and the watcher, which is the normal state of
this box — do not collide on the same file. A path assembled at runtime from
`$$t` is invisible to that rewrite: both runs write the same file.

## The fix

Spell the path in the recipe rather than deriving it in the loop body — the item
list is the usual place, e.g. carry the output name in each list entry so the
recipe text names `$(TESTTMP)/test_ws_skeleton26` literally. Failing that, add
the specific entries to `ALLOWED` in the guard **with a reason**.

## Gate

`make tools-devtest` green (Track T's guard passes), and the skeleton tests
still pass in the quick tier.

## Log
- 2026-08-25 — resolved, commit 5ca5c222d.
