---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`\"-\".join(\"hello\")` SEGFAULTS — pystr_join is reached by name and takes a TPyList, so a string handle is dereferenced as an object pointer; str is an iterable in CPython and join accepts it"
status: done
owner: claude-AN
---

# `sep.join(str)` dereferences a string handle as an object

- **Type:** bug (crash, no diagnostic) — **Track N**

## Repro

```python
print("-".join("hello"))
```

CPython: `h-e-l-l-o`.
pxx at pin **v291** and every pin before it: **Segmentation fault**, no
diagnostic, rc 139.

Not specific to non-ASCII — plain `"hello"` crashes.

## Cause

`pystr_join(const sep: AnsiString; l: TPyList)` is reached **by name**
(`FindProc('pystr_join')` in `PyStrMethodFinish`), not by overload resolution,
so nothing type-checks the argument. An `AnsiString` argument passes the string
HANDLE where a `TPyList` object pointer is expected and it is dereferenced.

This is exactly the shape of
`bug-nilpy-str-iterable-builtins-segfault-on-a-string-handle`, which was fixed
for `zip` / `enumerate` by wrapping a str argument in `PyIterArgAsList` (→
`pystr_charlist`). `join` has the same defect and was not covered by that fix —
a sibling that stayed broken, the pattern
`devdocs/dev/normalise-dont-special-case.md` warns about.

## Current state (2026-08-14, sha PENDING)

`feature-nilpy-text-string-kind` changed the symptom, not the bug: the argument
now arrives as something `pystr_join`'s item loop rejects, so it raises
`TypeError: sequence item 0: expected str instance` instead of crashing. Loud
beats silent, but it is still wrong — CPython joins it.

## Fix

Route a str argument to `pystr_join` through `PyIterArgAsList` (or call
`pystr_charlist` directly at the join site), the same way `zip`/`enumerate`
already do. Then **grep for the other by-name `FindProc` calls that take a
`TPyList`** — the whole point of this ticket is that the zip/enumerate fix left
siblings behind, and closing only `join` would repeat that.

CPython's `join` takes ANY iterable, so a generator/cursor argument is the next
shape after str; `PyDrainIfCursor` is already applied at that site for exactly
that reason, which shows the site is the right place for the str case too.

## Gate

`make compiler/pascal26` + the repro + `tools/gate.sh quick`. Add the repro to
the nilpy suite alongside `test_nilpy_str_counts_characters.npy`.

## 2026-08-14 — FIXED, and it was FOUR sites, not one

`"-".join("hello")` was the reported symptom. Grepping for siblings — which
this ticket demanded precisely because the zip/enumerate fix had left some
behind — turned up **three more crashes of the identical shape**, all of them
SIGSEGV with no diagnostic on every pin up to v292:

| construct | site |
| --- | --- |
| `"-".join(s)` | `PyStrMethodFinish`, beside the existing `PyDrainIfCursor` |
| `print(*s)` | the `print(*x)` arm — it raised "needs a list" for a str |
| `f(*s)` | `PyStarForwardCall` — `pystar_argc` read a 3-character string as **56** arguments |
| `[*s]` / `{*s}` | `PyParseListLiteralT`'s star arm, `TPyList.extend` |

`print(*s)` was the only one that was loud, and only by accident: its arity
check happened to reject a non-`tyClass` node before the handle reached pylib.

The fix is one call at each — `PyIterArgAsList`, which already existed for
zip/enumerate and returns a non-str node untouched. Two of the four are the
**shared normalisation points** (`PyStarOperandAsList`, `PyStarForwardCall`), so
every star path now passes through it: a fifth site would have to be a NEW star
path rather than a missed one.

### Why one grep was worth more than the fix

Each of these is two lines. What made them findable was cross-referencing the
frontend's by-name `FindProc('...')` calls against the pylib routines whose
parameter is a `TPyList` — the by-name calls are exactly the ones overload
resolution never type-checks, so they are the complete population of "a wrong
argument type gets dereferenced here". That list is short and worth re-running
whenever a new by-name lowering is added.

### Not fixed here, filed instead

`{*xs}` does not deduplicate (`len({*[1,1,2]})` is 3, CPython says 2) — the set
display's star arm calls `TPyList.extend` where its ordinary elements go through
`TPyList.add`. Pre-existing, reproduces with a plain list, and independent of
str: `bug-nilpy-set-star-spread-does-not-dedup`. Widening this ticket to cover
it would have meant a pylib change and a pin for a defect that has nothing to do
with string handles.

### Evidence

`test/test_nilpy_str_as_an_iterable_argument.npy` (`.expected` generated from
CPython) is byte-identical, covering all four constructs plus the shapes that
already worked (`sorted`, `max`/`min`, `list`, `tuple`, `enumerate`, `zip`,
`in`) so they stay working. No pylib change, so no pin needed.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
