---
prio: 55
track: A
type: bug
blocked-by: []
status: done
---

# A method call or subscript on a parenthesised expression fails (or crashes)

- **Type:** bug — **Track A** (the fix is in the SHARED `parser.inc`; the
  behaviour is NilPy's). Filed under A per the shared-internals rule and
  self-resolved under the combined-track assignment (sole-A confirmed
  2026-08-09).
- **Found:** 2026-08-09, realistic-program sweep, narrowing a file-write failure
  down to `("%s!\n" % t)`.

```python
("ab").upper()      # CPython AB;   pxx: error: expected newline after statement
(x).upper()         # same
("%d" % 5).zfill(3) # same
(x)[1]              # CPython b;    pxx: SIGSEGV
([1, 2])[0]         # same
```

Without the parentheses every one of these works, which is what makes it read
as a mystery: adding a grouping — the most reflexive thing a programmer does to
an expression — breaks it.

## Cause

`ParseFactorCore`'s grouped-postfix tail is **Pascal-shaped**: for `[` it builds
a raw `AN_INDEX` (Pascal array indexing) and for `.` it reads a record FIELD.
Neither is what a Python receiver means, and it ran in Python mode too. The raw
index over a `TPyList`/AnsiString handle is the SIGSEGV; the field read is the
parse error.

## Fix

In `PyExprMode`, stand down: leave `.` and `[` to ParseFactor's own Python
suffix loops, which run immediately afterwards and already handle str methods,
subscript and slice, variant runtime dispatch and class methods. `^` stays —
it has no Python spelling and no Python loop.

That is the same call the comment two lines below makes about not writing a
fourth copy of member dispatch: this tail was a third copy, and the Python side
already has the machinery.

## Verified

`test/test_nilpy_postfix_after_parens.npy` — grouped str methods, arithmetic and
`%` results, subscripts and slices over str/list/dict, chains that compose, a
class instance's method and field, an immediately-invoked lambda (still
callable), and a parenthesised TUPLE (still a tuple, not a grouping). Diffs
clean against CPython's own output.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN — the Pascal
arm is unchanged by construction (the guard only removes the PyExprMode case)
and the self-host exercises it heavily.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
