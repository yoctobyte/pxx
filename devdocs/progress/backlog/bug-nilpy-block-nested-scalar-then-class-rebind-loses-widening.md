---
prio: 40
track: N
type: bug
blocked-by: []
---

# A scalar-then-class rebind INSIDE a nested block loses the widening entirely

- **Type:** bug (NilPy, **silent wrong value**) — **Track N**
- **Found:** 2026-08-09 while gating
  [[bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch]]
- **Pre-existing:** reproduced identically on the PINNED binary, so it is not a
  regression from that fix.

## Measured

```python
class Bare:
    def __init__(self, n):
        self.n = n

if True:
    b = 0
    b = Bare(1)
    print(b + Bare(2))     # CPython: TypeError    pxx: -1094713184
```

At module level the same three lines are correct (`b` widens to a variant and
the addition raises TypeError). Inside a nested block the widening is lost and
the two instance HANDLES are added — a different plausible number every run.

## Narrowed

- `if True:` and `try:` behave the same, so it is **nesting**, not the
  statement kind.
- Remove the `b = 0` and it is correct — so it is the scalar-then-class
  REBIND specifically, not block-scoped binding in general.
- `Bare(1) + Bare(2)` and a module-level `b = 0; b = Bare(1); b + Bare(2)` both
  raise correctly. Only the combination bites.

## Why it matters

Silent and arithmetic: the program computes a plausible integer where CPython
raises. It is also the shape a real file has — bindings inside an `if`, a `try`,
or a loop are ordinary Python, and the module-level form is the artificial one.

## Likely cause (to measure, not assume)

`PyCollectModuleLocalsAST` walks module-level statements and tracks block depth
(`blockIsDef[]`). The suspicion is that a binding inside a non-def block is
harvested differently from a top-level one, so the two bindings of `b` are not
unioned and the LAST one wins as a static class. Confirm with
`PXXDBG=n.locals`: at module level `b` should report `tk=22`, and the nested
form is expected to report `tk=6 rec=<Bare>`.

Note the sibling that WAS fixed: a name bound to two unrelated CLASSES now
widens to a variant ([[bug-nilpy-local-reassigned-across-classes-keeps-one-static-class]],
2026-08-08) — that fix went into the same two harvest loops plus
`PyNoteLocalType`, so those three sites are the place to look, and its `Poly`
flag is the worked example.

## Gate

`.npy` diffed against CPython: the repro above under `if`, `try`, `for` and
`while`; the module-level control that already works; and a case where the
nested rebind is between two SCALARS (int then str), which must keep widening.
