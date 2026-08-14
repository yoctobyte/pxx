---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`{*xs}` does not deduplicate — the set literal's star-spread arm calls TPyList.extend, bypassing the TPyList.add the non-star elements go through, so `len({*[1,1,2]})` is 3 where CPython says 2"
status: done
owner: claude-AN
---

# `{*xs}` skips the set's deduplication

- **Type:** bug (silent wrong value) — **Track N**

## Repro

```python
print(len({*[1, 1, 2]}))   # CPython 2, pxx 3
print(len({1, 1, 2}))      # CPython 2, pxx 2  <- the non-star path is right
print(len({*"aab"}))       # CPython 2, pxx 3
```

Reproduced on pin **v292** and earlier. Silent: the result is still a set-shaped
value and still prints like one, just with an extra element.

## Cause

`PyParseListLiteralT(opener, closer, dedup)` builds both list and set displays
into a `TPyList`. When `dedup` is set it routes each ordinary element through
`TPyList.add` — added by `bug-nilpy-set-literal-does-not-deduplicate`, which
fixed exactly this defect for the non-star path.

The **star-spread arm** in the same procedure calls `TPyList.extend`
unconditionally, and `extend` appends. So the fix for the sibling case landed on
one arm of the same procedure and not the other — the shape
`devdocs/dev/normalise-dont-special-case.md` describes, and the second time this
literal parser has shown it.

## Fix

Make the star arm honour `dedup`: either a `TPyList.extend_unique` in
`compiler/builtin/pylib.pas` (a pylib change, so it needs a pin), or emit a loop
of `add` calls, or extend-then-dedup in place. Prefer whichever leaves ONE
mechanism deciding "does this display deduplicate" — the current split is what
produced the bug.

Check the dict-display and comprehension paths for the same split while there:
`{k: v for ...}` and `{x for x in ...}` also build a marked `TPyList`.

## Gate

`make compiler/pascal26` + the repro + `tools/gate.sh quick`; a pin only if
pylib changes. Add the repro to
`test/test_nilpy_str_as_an_iterable_argument.npy`, which carries a
`sorted({*s})` assertion and deliberately does NOT assert the length today —
that omission is this ticket.

## 2026-08-14 — FIXED, and pylib needed nothing

`PyParseListLiteralT`'s star arm now picks its bulk operation from the same
`dedup` flag that already picks the per-element one:

| | per element | spread |
| --- | --- | --- |
| list display | `append_self` | `extend` |
| set display | `add` | **`setupdate`** (was `extend`) |

`TPyList.setupdate` — `for i := 0 to other.count - 1 do Self.add(other.at(i))` —
already existed for `set.update`, so there was nothing to add to pylib and **no
pin is needed**. That is the outcome worth noting: the ticket proposed writing an
`extend_unique`, and the deduplicating bulk add was already there under the name
Python gives it. Checking for the existing mechanism before adding one is what
kept this from becoming a second way to do the same thing.

One thing still decides whether a display deduplicates.

### The siblings the ticket asked about are already right

Measured rather than assumed, since the whole ticket is about a fix that landed
on one arm and not another:

```
{x for x in [1,1,2,2,3]}   -> 3 elements     set comprehension: correct
{x % 2 for x in xs}        -> [0, 1]         correct
{k: 1 for k in "aab"}      -> 2 keys         dict comprehension: correct
set([1,1,2]), set("aab")   -> correct
```

Only the display's star arm was wrong.

### Gate

`test/test_nilpy_set_star_spread_dedups.npy` + `.expected` from CPython. It
carries the LIST rows deliberately — `[*[1,1,2]]` must still be `[1, 1, 2]`,
which is the failure a "make it dedup" fix invites. `make compiler/pascal26`
fixedpoint + `tools/gate.sh quick`.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
