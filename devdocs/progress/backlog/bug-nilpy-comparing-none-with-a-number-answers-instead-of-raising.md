---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`min(3, None)` answers None where CPython raises TypeError — pyvar_gt orders None against a number instead of refusing. Low priority: comparing None is a bug in the calling program, and every shape CPython accepts is unaffected. But it is the wrong DIRECTION of laxity: we answer a question CPython refuses to answer, silently."
---

# Comparing None with a number answers instead of raising

```python
print(min(3, None))     # CPython: TypeError   pxx: None
```

Pre-existing (the pinned compiler agrees), found 2026-08-13 while fixing
`min`/`max` with `key=None` — the guard added there deliberately does NOT cover
this shape, so that a mistaken comparison keeps failing rather than being
absorbed into the key=None escape.

## Why it is worth filing despite the low priority

This dialect is deliberately lax where CPython is strict, and that is fine when
the laxity means "we accept a program CPython rejects". Here it means something
weaker: **we answer a comparison that has no answer.** `None < 3` is not a
question with a right result, so returning one is a silent wrong value in a
program that has a bug — exactly the case where a diagnostic is worth more than
tolerance ("feedback is informative").

CPython's rule is not historic either: `None` is orderless against numbers by
design, and every dynamic language that allows it regrets it.

## Where

`pyvar_gt` (pylib) orders a VT_EMPTY payload as 0 against a number rather than
refusing. Any of `<`, `<=`, `>`, `>=` on None-vs-number reaches it; `==` and
`!=` are FINE and must stay (CPython allows those and answers False/True).

## Gate

`min(3, None)`, `3 < None`, `None > 3`, `sorted([1, None])` diffed against
CPython — each raising TypeError with the operand types named — and `None == 3`
/ `None != 3` still answering False/True. Plus the `key=None` rows of
`test_nilpy_min_max_key_none` unchanged, since they share the routine.
