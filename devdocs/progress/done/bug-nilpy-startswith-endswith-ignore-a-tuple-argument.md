---
prio: 40
track: N
type: bug
blocked-by: []
owner: agent-AN
---

# `startswith`/`endswith` with a TUPLE of prefixes silently answered False

- **Type:** bug (NilPy, **silent wrong answer**) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of the str surface against
  CPython (`tools/pydiff.py`), not by a report.
- **Status:** done

```python
s = "Hello, World"
print(s.startswith(("X", "He")))   # CPython True    pxx False
print(s.endswith(("d", "Z")))      # CPython True    pxx False
```

The pylib entry took a single `AnsiString`, so a tuple argument became text
that matches nothing.

## Why this one mattered more than its size

The failure direction hides completely. A tuple of prefixes is written as a
GUARD — `if name.startswith(("test_", "check_")):` — so the bug does not produce
a wrong-looking value anywhere; the branch simply never fires and the program
takes the other path in silence. Nothing to grep for, nothing to breakpoint.

## Fix

A Variant-taking `pystr_startswith_any` / `pystr_endswith_any`, selected by the
frontend **only when the argument is not statically a string**. That keeps the
hot `sys.platform.startswith("win")` path on its plain call, and makes one entry
point serve a tuple literal, a tuple held in a variable, and a value that only
turns out to be a tuple at run time.

One name per shape rather than an overload, following the convention the `-9`
argument row already documents: `FindProc` resolves by name and never consults
overloads ([[project_findproc_by_name_ignores_overloads]]).

## Deliberately not changed

`s.startswith(["X", "He"])` with a LIST raises TypeError in CPython and answers
True here. Ordinary NilPy laxity under the upward-compatibility rule — no
working CPython program can observe it — so the test says so rather than
pinning it.

## Gate
`test/test_nilpy_startswith_tuple.{npy,expected}` (`.expected` from CPython):
tuple literal, tuple in a variable, tuple from a def (the variant case), empty
tuple, plain string both ways, the start/end window, and a windowed miss.

## 2026-08-09 — VERIFIED already fixed; this is a bookkeeping close

Not new work. The fix and its test had landed but the ticket was never moved out
of `backlog/`, so it kept being offered by `progress.sh ready`. Verified at HEAD
before moving it rather than trusting the write-up:

- `test/test_nilpy_startswith_tuple.npy` passes against its CPython-derived
  `.expected`, and is wired into `make test-nilpy` (Makefile ~1154).
- Re-probed by hand, including the shape the ticket says hides — a tuple guard
  through a VARIANT receiver (`for v in xs: v.startswith(("he", "x"))`) — and a
  tuple that must MISS. All match CPython.

Recorded because "the ticket is the record": a fixed-but-unmoved ticket costs
the next agent a full read-and-reproduce cycle to discover there is nothing to
do, which is exactly what happened here.

## Log
- 2026-08-09 — resolved, commit f0ce6cd58.
