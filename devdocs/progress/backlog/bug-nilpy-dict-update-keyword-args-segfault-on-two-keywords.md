---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`d.update(a=1)` lowers correctly for ONE keyword and SEGFAULTS for two, through the same builder that makes `dict(a=1, b=2)` correct — so the method-argument path mishandles the builder's hoisted setitem statements. Not shipped for that reason; `dict(...)` is. Also: `d.update(**e)` is refused by a route that is none of parser.inc's five argument loops."
---

# `d.update(a=1, b=2)` segfaults — the method half of keywords-are-KEYS

- **Type:** bug (memory corruption, but currently UNREACHABLE — the lowering is
  gated off) — **Track N**
- **Found:** 2026-08-13, landing the `dict(a=1)` half of
  [[bug-nilpy-small-builtin-surface-gaps-found-by-the-2026-08-13-sweep]].
- **Reachable how:** only by widening `PyKeywordsAreKeys` (pyparser.inc) from
  `dict` back to `dict` + `TPyDict.update`, which is a one-line change and is
  how the measurements below were taken.

## What was measured

`PyBuildKeywordDict` builds the dict a keyword run describes — hoisted temp,
one `setitem` per pair, `pydict_merge` for a `**` spread, exactly as a `{...}`
literal is built — and the caller passes it as the single dict argument both
`dict()` and `update()` already take. With that builder wired to BOTH callees:

| shape | result |
| --- | --- |
| `dict(z=7, y=8)` | correct |
| `d.update({"z": 7, "y": 8})` | correct |
| `d.update(z=6)` | correct |
| `d.update(z=7, y=8)` | **SEGFAULT** |

The dict it builds is right (row 1) and the dict it is handed is right (row 2),
so the fault is in what the METHOD-argument path does with the builder's
**hoisted** statements. Prime suspect, unconfirmed: a trial parse that rewinds
and replays them (`PyHoistPark` / `PyHoistRestore` / `PyHoistMerge`) — the shape
recorded in `devdocs/dev/` and in several sibling tickets. One keyword hides it
because replaying one idempotent `setitem` changes nothing.

## The `**` form is refused somewhere unexpected — read this before hunting

`g.update(**src)` reports `expected expression`, from ParseFactor's final else
(i.e. something called ParseFactor with `*` as the current token). That error
does **not** come from any of parser.inc's five method-argument loops. All five
were instrumented — a `Warn` in `PyKeywordsAreKeys` printing the callee name
every time it is asked — and while compiling that one line **not one of them is
reached**: the last probe fires deep inside pylib, then the error.

So the route that handles `recv.method(**expr)` is none of: the arity-driven
method loop, the field-receiver loop, the plain class-method loop, the
metaclass-ctor loop, the plain-call loop. Find it first. Patching loops one at a
time cost four rebuilds and found nothing.

(The plain keyword form `d.update(z=6)` DOES reach the arity-driven loop. Same
construct, two routes — `devdocs/dev/normalise-dont-special-case.md`.)

## Gate

`d.update(a=1)`, `d.update(a=1, b=2)`, `d.update(**e)` and
`d.update(other, a=1)` (CPython allows the mixed form; today's builder does not
and says so) all diffed against CPython, plus the existing
`test/test_nilpy_dict_keyword_args.npy` rows staying green.

## 2026-08-13 — the ENABLING CONDITION found, and the segfault reproduced behind it

Nothing shipped; this is the diagnosis, banked. Two facts, both measured.

### 1. `PyKeywordsAreKeys` could never have matched a METHOD

It compares `Procs[mpi].Name` against `'dict'`. A method's Procs entry is named
**qualified** — `TPyDict.update` — so the predicate answered False for every
method, whatever the call site did. That is why the earlier session's
instrumentation "was not reached by any of the five argument loops": the loops
were fine, the predicate said no before any of them mattered.

Measured with a one-shot probe (a `PyKwSite` global set at each of the nine
`PyKwArgIndex` call sites and printed in its error): `d.update(z=6)` reaches
**parser.inc's arity-driven method loop**, which has consulted
`PyKwDictArgNode` all along. So there was never a missing call site — only a
name comparison that could not succeed.

### 2. With the name fixed, the reported symptom reproduces exactly

`CaseEqual(Procs[mpi].Name, 'TPyDict.update')`:

| shape | result |
| --- | --- |
| `d.update(z=6)` | correct |
| `d.update(z=7)` onto an existing `z` | correct |
| `d.update(z=7, y=8)` | **SEGFAULT** |
| `d.update(z=7, y=8, x=9)` | **SEGFAULT** |
| `d.update({"z": 7, "y": 8})` | correct |
| `dict(z=7, y=8)` | correct |

So the ticket's headline is confirmed rather than explained: one keyword is
fine, two corrupt memory, and the SAME builder feeding `dict(...)` in the same
program is correct with two.

The faulting instruction is `mov (%rax),%rax` after `rax := ptr - 8` — a
length/refcount word read through a bad handle, the shape of a use-after-free,
inside pylib (no DWARF there).

### Ruled out while here

The obvious suspect — the hoisted `setitem` statement being typed `tyClass`, so
each hoisted statement releases the returned Self and two releases free the dict
— is **not** it, or not it alone: `PyParseDictLiteral` builds `{"z": 7, "y": 8}`
with an identically-typed, identically-hoisted `setitem` per pair, in the same
argument position, and is correct.

### What to try next

Diff the two hoist SEQUENCES rather than the builders — dump `PXXDBG a.ir` for
`d.update({...})` and for the keyword form with the predicate re-enabled, and
compare where the temp is assigned relative to the receiver's evaluation. The
one structural difference left is that the keyword form's hoists are queued
*while the method's argument list is being parsed* and the literal's are queued
*while its own literal is*, which is the trial-parse/hoist-queue interaction
[[project_trial_parse_rewind_leaves_its_hoists_queued]] describes.

Reverted rather than shipped: a form correct with one keyword and corrupting
memory with two is worse than the compile error it replaces, which is the same
call the earlier session made.
