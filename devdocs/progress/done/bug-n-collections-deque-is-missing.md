---
slug: bug-n-collections-deque-is-missing
track: N
prio: 40
type: bug
status: done
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, stdlib, collections, lekkerzeilen]
blocked-by: []
summary: "RESOLVED 2026-09-09 -- TPyDeque in compiler/builtin/pylib.pas plus a `collections.deque` entry in the frontend stdlib-call table; all three spellings now agree with CPython. THE QUALIFIED SPELLING WAS THE WHOLE PROBLEM and is the only one a real program writes (every stdlib use site in the lekkerzeilen corpus is `module.name`; none is `from module import name`): bare `deque()` and the from-import needed nothing, while `collections.deque()` failed because `collections` HAS a backing unit -- lib/rtl/collections.pas, a Pascal generic TList that shares the name and nothing else. Routed through the stdlib table rather than by changing what `collections` resolves to, because that table is consulted BEFORE unit-member lookup (measured with math.pow, which resolves through it while lib/rtl/math.pas is loaded), so it needs no resolver-order change and leaves collections.abc untouched. popleft is O(1) AMORTISED because the caller is a flood fill. IT DOES NOT UNBLOCK chart: that was a first-wall count, not measured as sufficient, and chart now stops at the open-world dispatch blocker."
---

# Repro

```
$ ./compiler/pascal26 lekkerzeilen/chart.py out
pascal26:119: error: no member deque came of the qualifier collections
```

# Note on scope

The usage to satisfy first is the ring-buffer one: bounded `deque(maxlen=N)`,
`append`, `popleft`, iteration and `len`. That is what a scrolling chart wants
and it is the common case in real code generally; the full deque API
(`rotate`, `extendleft`, negative-index insert) can follow if anything asks.

## RESOLVED 2026-09-09 (frankB)

`TPyDeque` in `compiler/builtin/pylib.pas`, plus a `collections.deque` entry in
the frontend's stdlib-call table. All three spellings now work and agree with
CPython.

**The qualified spelling was the whole problem, and it is the only one a real
program writes.** Bare `deque()` and `from collections import deque` needed
nothing but the pylib proc, because plain pylib procs resolve with no import at
all. `collections.deque()` failed because `collections` HAS a backing unit —
`lib/rtl/collections.pas`, a Pascal generic `TList` that shares the name and
nothing else — so the qualifier resolved against it and asked it for a member it
has never had. Census of the lekkerzeilen corpus: **every** stdlib use site is
`module.name`; not one is `from module import name`.

**Routed through `PyStdlibCallProc` rather than by changing what `collections`
resolves to.** That table is consulted BEFORE unit-member lookup — measured with
`math.pow`, which resolves through it while `lib/rtl/math.pas` exists and is
loaded — so it needs no resolver-order change and leaves `collections.abc`
(a real shim, matched on the full dotted path) untouched.

**The target is `pydeque_new`, not `deque`, and that is load-bearing.** The
table resolves with a plain `FindProc` by NAME, so mapping it to `deque` let a
program that also wrote `def deque(): ...` have its OWN function called for
`collections.deque()` — a silently wrong object where CPython gives the
module's deque. Caught by a control row, not by the feature test. `math.pow`
escapes the same hazard only because it happens to map to a differently spelled
proc (`Power`) — an accident of spelling, not a guard, and worth knowing before
the next entry is added.

**O(1) amortised popleft, not list.pop(0).** The measured caller is a
breadth-first flood fill over a chart raster where every cell enters the queue
once; `pop(0)` would make the traversal quadratic in the pixel count. TPyDeque
is a TPyList plus a head index, with compaction only once the dead prefix is
half the buffer. The test asserts 20 000 append/popleft (30 ms).

**It does not unblock `chart`.** After landing, chart's wall moved from this to
`no class declares a method or callable field .read_g...` — the open-world
dispatch blocker. See the array ticket and the umbrella for why a first-error
census over-counts; the census total is unchanged at 8 of 23.

Filed alongside: `bug-n-collections-counter-is-unreachable-through-its-qualified-spelling`,
which is the same gap for `Counter` and was deliberately NOT fixed the same way —
that table selects by arity and cannot select by type, and Counter's two
1-argument overloads differ only by type, so an entry would trade an honest
refusal for a silently wrong count.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
