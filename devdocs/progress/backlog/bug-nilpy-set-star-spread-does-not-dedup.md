---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`{*xs}` does not deduplicate — the set literal's star-spread arm calls TPyList.extend, bypassing the TPyList.add the non-star elements go through, so `len({*[1,1,2]})` is 3 where CPython says 2"
status: backlog
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
