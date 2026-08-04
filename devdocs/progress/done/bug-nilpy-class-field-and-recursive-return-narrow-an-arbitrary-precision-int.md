---
track: N
prio: 55
type: bug
summary: "A class FIELD and a RECURSIVE def's result are typed from their first int-shaped initialiser, so an arbitrary-precision value assigned later wraps at 2^64"
status: done
owner: claude-AN
---

# A class field and a recursive return narrow an arbitrary-precision int

```python
class C:
    def __init__(self):
        self.v = 1
    def grow(self):
        for k in range(70):
            self.v = self.v * 2
c = C()
c.grow()
print(c.v)            # CPython: 1180591620717411303424     pxx: 0

def fa(n):
    if n <= 1:
        return 1
    return n * fa(n - 1)
print(fa(25))         # CPython: 15511210043330985984000000  pxx: 7034535277573963776
```

The last two open sites from
[[task-n-enumerate-the-promo-surface-by-output-diff]], split out so the
promotable-int default can land without them: everything the sweep found in
locals, module scope, operators, builtins, containers, formatting and
call/return boundaries is fixed, and both of these are the SAME residual shape
in two different binding kinds.

## The shape

A binding's type is inferred from the first int-shaped thing assigned to it and
then never widened when a promotable value reaches it later:

- **field** — the `__init__` pre-pass types `self.v = 1` as `tyInt64`, so the
  field is a machine-int cell and the promo store narrows mod 2^64 (2^70 -> 0).
  `self.v: int = 0` behaves the same way; there is no annotation that says
  "arbitrary precision", which is the point of the option-1 default.
- **recursive return** — the return-type chase deliberately re-derives a promo
  result from TOKENS in both passes (a PyLocals-derived answer differs between
  the shell pre-pass and the body pass, which is a silent ABI mismatch). For a
  self-recursive body the chase sees `n * fa(...)`, cannot type the recursive
  call, and settles on the int default. A NON-recursive def returning the same
  accumulator is already correct — it boxes to a variant.

## Why they were not fixed with the rest

Both need a *widening* pass rather than a typing arm: the binding is created
before the promotable assignment is seen, so the fix is to re-visit it, not to
type it better at first sight. For the field that means the class pre-pass
gaining a fixpoint like the module pre-pass already has; for the recursion it
means the return chase treating a self-call as "unknown, retry" instead of
falling to the int default.

Do NOT fix the return case by trusting PyLocals in the body pass — that is the
ABI mismatch the existing comment at the chase warns about, and it was already
paid for once.

## Method

Diff stdout against CPython, never exit status — the whole reason the earlier
survey missed four sites. `tools/pydiff.py` or the sweep harness in
[[task-n-enumerate-the-promo-surface-by-output-diff]].

## Gate

Per-fix loop. A field/recursion `.npy` test diffed against CPython; check
`ls test/ | grep -E 'promo|bigint'` for an existing file to extend.

## Log
- 2026-08-04 — resolved, commit PENDING-COMMIT.
