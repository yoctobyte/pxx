---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`return lambda x: ...` yields a value that is NOT callable — `TypeError: object is not callable (no __call__)` where CPython calls it. Binding the same lambda to a local first (`g = lambda ...; return g`) works, so the lift is fine and it is the RETURN of the lambda expression that loses the callable tag."
---

# A lambda returned directly is not callable

- **Type:** bug (NilPy frontend) — **Track N** (`compiler/pyparser.inc`).
- **Filed by:** frank2 on Track A, 2026-08-19, while probing
  [[refactor-a-one-signature-record-for-every-callable-carrier]]. Found by a
  probe, not by the ticket; unrelated to that refactor (it reproduces on the
  pinned compiler too).

## Measured at HEAD (9477001a8, self-host converged)

```python
def mk(k):
    return lambda x, y=2: x * 100 + y + k
a = mk(1)
print(a(5))
print(a(5, 9))
```

| | output |
| --- | --- |
| CPython | `503` / `510` |
| pxx | `Unhandled exception: TypeError: object is not callable (no __call__)` |

## The shape that WORKS — same lambda, one local in between

```python
def mk(k):
    g = lambda x, y=k: x * 100 + y
    return g
a = mk(1); b = mk(7)
print(a(5), b(5), a(x=5))     # 501 507 501, matching CPython
```

So the lift, the captures, the per-instance defaults and the keyword path are
all fine. What differs is only that the lambda expression is the operand of
`return` rather than of an assignment — the callable BOXING (`pyvar_of_callable`,
which is what stamps VT_CALLABLE/the bound-fn tag) is presumably applied on the
assignment path and not on the return path, so the caller receives a payload
with a tag that `PyNotCallable`'s allow-list rejects.

## Why it matters

`return lambda ...` is the single most idiomatic way to write a closure factory
in Python, and it fails while its two-line spelling works — a difference no
Python author would predict. It is also a silent-looking failure at the CALL
site, far from the `return` that caused it.

## Suggested first look

`PyBoxCallableValue` / `PyNodeIsCallableValue` (`compiler/pyparser.inc`) decide
where a callable-producing node gets boxed. Check whether the `return`
statement's expression runs through the same box as an assignment's RHS — the
allow-list already carries the whole `pyboundfn_*` chain, so the likely gap is
that the return path never asks.
