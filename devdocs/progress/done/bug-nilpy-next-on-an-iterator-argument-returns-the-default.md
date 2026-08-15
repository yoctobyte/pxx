---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`next((c for c in cs if ...), dflt)` answered the DEFAULT — the `next` arm bound statically to `pynext_first_or(l: TPyList; ...)`, so a TPyIter arriving at a TPyList parameter was misread. Regression from the genexpr-cursor fix, caught by Track T on test_nilpy_sorted_pairs."
status: done
owner: claude-AN
---

# `next()` over an iterator argument returns the default

Reported by Track T as an open regression:
`test-core#src:test/test_nilpy_sorted_pairs.npy bad=bb845b13ceb3`.

```python
cs = ["a", "bb", "ccc"]
print(next((c for c in cs if len(c) == 2), "none"))   # CPython bb    pxx none
```

Silent — a plausible wrong value, never a crash.

## Cause

Follow-on of [[bug-nilpy-a-generator-expression-is-not-consumed-once]]
(`ba6022847`), which made a genexpr answer a real `TPyIter` cursor instead of a
materialised list. The `next` arm in `compiler/parser.inc` still selected
`pynext_first_or(l: TPyList; const dflt: Variant)` **statically**, so the cursor
handle arrived at a `TPyList` parameter and was misread; the "empty" reading
returned the default. Bound to a name first (`g = (...); next(g, "none")`) the
value went through the variant path and was right — which is why the suite's
genexpr tests stayed green and only the inline spelling broke.

The shape is the recurring one: a static callee choice where the operand's type
is a run-time fact.

## Fix

`compiler/builtin/pylib.pas` — `pynext_v(const v)` / `pynext_or_v(const v, dflt)`:
a `TPyIter` advances via `pyiter_has` / `pyiter_next` / `pyiter_next_or`,
everything else falls through to `pynext_first(pylist_v(v))` as before.
`compiler/parser.inc`'s `next` arm boxes both operands with `PyForceVariant` and
calls those.

Gate: `gate.sh quick` GREEN, self-host fixedpoint; pinned v339 (pylib changed).
Verified `sorted_pairs`, `genexpr`, `genexpr_is_consumed_once`,
`bare_genexpr_arguments`, `iterator_protocol` byte-identical to CPython.
