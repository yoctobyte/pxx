---
track: N
prio: 65
status: done
type: feature
---

# `iter(xs)` is undefined — the explicit iterator protocol

```python
it = iter(xs)          # error: undefined variable (iter)
print(next(it), next(it))
print(list(it))        # the rest, from where next() left off
```

`next()` already exists for a bare generator expression (`next(x for x in xs)`),
so the gap is `iter` itself and, with it, the idea of a RESUMABLE position over
a container. That second half is the real work: `list(it)` after two `next()`
calls must yield only the remainder, so the iterator has to hold state that
survives being passed around.

Walls visibly as an undefined name.

Related and deliberately not merged: `feature-nilpy-yield-outside-a-for-loop`
records that generators are unimplemented full stop. A user-defined `__iter__` /
`__next__` pair is a third piece again. This ticket is only the builtin over an
existing container, which is the cheapest of the three and the one real code
reaches for first.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `iter` on a
list, tuple, set, dict (keys) and string; `next()` to exhaustion raising
StopIteration; `next(it, default)`; and consuming the remainder with `list()`
and with a `for` after partial consumption.

---

## ALREADY DELIVERED — closed 2026-08-30 (frankwasm)

**The feature landed under a different ticket and this one was never closed.**
`0e171a8d1`, "feat(N): TPyIter cursors — iter()/next(), and a for-loop that
consumes one", filed under
[[feature-nilpy-lazy-iterator-objects]]. This ticket's opening claim — "`iter(xs)`
is undefined ... walls visibly as an undefined name" — is no longer true at HEAD.

Its exact repro, run before claiming:

```python
xs = [1, 2, 3, 4]
it = iter(xs)
print(next(it), next(it))     # 1 2
print(list(it))               # [3, 4]
```

matches CPython, **including the half this ticket called "the real work"** — a
resumable position, so `list(it)` after two `next()` calls yields only the
remainder.

Every item of the Gate above was then run against CPython and every one passes:
`iter` over a list, tuple, set, dict (keys) and string; `next()` to exhaustion
raising `StopIteration`; `next(it, default)`; consuming the remainder with
`list()` and with a `for` after partial consumption.

### What was actually missing was the ASSERTIONS, not the code

`test/test_nilpy_iter_next_cursor.npy` landed with the feature and already
pinned most of that gate — plus resume-after-`break`, `continue`, and
tuple-unpack in a `for`. Two of this ticket's gate rows had no coverage:
**tuple** and **set** as `iter()` sources. Added there rather than in a new
file, since a second file asserting the same cursor would be the duplicate this
repo warns about.

The set row goes through `sorted()`: CPython does not specify set iteration
ORDER, so asserting the raw sequence would pin an implementation detail and
fail for something that is not a defect. The property under test is that the
cursor yields every element once.

Both Makefile rules for that test were updated — it is registered **twice**
(lines 592 and 10485), and changing one would have left the other failing.

### Note on this ticket's Gate line

It says `make test-nilpy`, which is **superseded** by CLAUDE.md's per-fix loop
(`decide-gate-line-convention`, 2026-08-01). Gate run here: `make
compiler/pascal26` — the byte-identical self-host fixedpoint — plus the test
above and a CPython diff of every gate row. Left in place rather than edited:
the line is a record of what the ticket asked for when it was written.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
