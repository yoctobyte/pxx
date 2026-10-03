---
slug: bug-n-a-for-loop-over-a-fresh-call-result-is-released-twice
title: a for loop over a fresh call result is released twice
summary: >
  `for x in mk(k)`, `for x in r.again()`, `for row in db.execute(..)` -- a
  loop (or comprehension) inside a def over a FRESH object returned by a
  call, of a class with __iter__ -- released that object twice: "RELEASE of
  a FREED object" under -dPXX_HEAP_DEBUG, silent otherwise, until a second
  thread allocated into the freed block. That is what crashed lekkerzeilen
  intermittently: its sqlite tile loader thread walks a fresh cursor, and 4
  runs in 8 died with IndexError, "object is not subscriptable" or
  `_admit_foliage()` called with garbage arguments. FIXED 2026-10-03
  (frankuser): the loop takes pylib's _owned cursor entry only for a
  construction.
track: N
type: bug
prio: 90
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

### How it was found

Measuring lekkerzeilen's leak slope headless (`--shot`, Xvfb, `--region
rijn`), the compiled demo died in about half its runs, with a different
exception each time. A lock bisection in a scratch copy of the demo
(never in its own tree) narrowed it to the loader thread's `tile.load()`:
loading synchronously gave 8/8 identical runs, and a lock around `load()`
alone gave 0 crashes in 8. Extracted: a loader thread iterating
`for ... in db.execute(..)` while the main thread allocates failed 12 runs
of 12 (SIGSEGV, IndexError, "too many values to unpack (expected 2, got 6)"
-- the main thread unpacking one of the loader's rows). `fetchall()` and a
`fetchone()` loop were clean, and so was a single thread under
-dPXX_HEAP_DEBUG at module level. Inside a def, single-threaded, HEAP_DEBUG
reported the double release outright, so threads were only the amplifier.

### The mechanism

PyParseForIn wrapped a user iterable whose value is OWNED
(PyCallYieldsOwnedObj) in `pyiter_of_userobj_owned`, which drops the
caller's reference once the cursor holds its own. For a construction that
is the only release. For an owned CALL result it is the second one:
IRLowerCallArg spills an object-returning proc call to an owning temp even
in argument position 0, and that temp releases at scope exit. Module level
was spared because the loop's value was held differently there.

The loop now takes the _owned entry only when the value (read through a
fold, whose value is its last element) is a construction, the one owned
value that spill leaves alone in position 0.

### Verified

- test_nilpy_a_for_loop_over_a_fresh_call_result_releases_it_once: a NilPy
  factory, a method result, a chained `mk(k).again()`, a dunder result
  `Rows(k) + 1`, list comprehensions and a generator expression over them,
  plus the construction and old-style `__getitem__` shapes that were already
  right. b2bf8a845f: 21 releases of a freed object in the no-argument run;
  now none, byte-identical to CPython, also on i386; census flat (75 live
  after 3000 passes, control trips).
- test_nilpy_a_cursor_loop_in_a_thread_releases_each_row_cursor_once
  (--threadsafe, sqlite): 10 of 10 runs failed on b2bf8a845f, 0 of 10 now.
- lekkerzeilen's own unmodified source, built at the fix and run 8 times
  under Xvfb (`--shot --for 20 --region rijn`): 8 clean runs, against 4
  crashes in 8 before.

### Not this ticket

The demo's leak slope: see
bug-n-the-demo-leaks-16-mb-per-two-minutes-on-a-real-world-and-it-is-not-in-the-render-path
for the measurement taken the same day.
