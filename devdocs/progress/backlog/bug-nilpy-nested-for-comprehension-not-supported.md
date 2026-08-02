---
track: N
prio: 45
type: bug
summary: "A comprehension with TWO for-clauses — [c for r in rows for c in r] — fails with 'undefined variable (c)'; the flatten idiom is unavailable"
---

# `[c for r in rows for c in r]` — a second `for` clause is not supported

- **Type:** bug / missing language feature (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping nested containers and comprehensions vs CPython.
- **Loud**: a compile error, though a confusing one.

```python
rows = [[1, 2], [3, 4]]
print([c for r in rows for c in r])     # CPython [1, 2, 3, 4]
```
```
pascal26:10: error: undefined variable (c)
  near:   flat   c >>> for r
```

The diagnostic names the ELEMENT expression's variable (`c`) rather than the
unsupported second `for`, so it reads as a scoping bug rather than a missing
feature. Whatever else is done here, that message is worth improving on its own:
the parser evidently binds only the first `for` clause's target, then fails to
resolve the element expression against the second.

## What DOES work

Single-`for` comprehensions are solid, including the filter and the dict form —
all verified against CPython in the same sweep:

```python
[x * 2 for x in l]
[x for x in l if x > 1]
[[c * 2 for c in r] for r in rows]        # NESTED comprehensions are fine
{k: len(v) for k, v in d.items()}
[x for x in range(10) if x % 3 == 0]
```

Note the third line: a comprehension *inside* another comprehension's element
expression works. It is specifically a second `for` **clause in the same
comprehension** that does not.

## Why it matters

`[c for r in rows for c in r]` is the standard flatten idiom, and the standard
answer to "how do I flatten a list of lists" in Python. Its absence pushes code
onto an explicit nested loop, which is fine, but the failure mode — a compile
error naming a variable the user did clearly bind — costs time before that
conclusion is reached.

## Shape of the fix

`PyParseForIn` already desugars one `for` clause into a counted loop whose body
is `target.append(EXPR)`, with `PyCompTarget` carrying the accumulator. A second
clause is the same desugar NESTED inside the first, with the element expression
and any `if` filter moving to the innermost body. The pieces that need care:

- the hidden loop-variable renaming (`PyCompHiddenLoopName`, which exists so a
  comprehension's target does not clobber an outer binding) has to run per
  clause, and the element expression must see BOTH hidden names
- the `if` filter currently attaches to the single loop; with two clauses Python
  allows a filter after either, and it gates only the loops inside it
- `PyCompExprStart` / the closer scan that hides the filter's `if` from the ITER
  parser assumes one clause

## Gate

A `.npy` diffed against CPython: the flatten idiom; two clauses with a filter on
the outer, on the inner, and on both; a dict comprehension with two clauses;
three clauses; and single-clause comprehensions plus comprehension-inside-a-
comprehension as regression controls.
