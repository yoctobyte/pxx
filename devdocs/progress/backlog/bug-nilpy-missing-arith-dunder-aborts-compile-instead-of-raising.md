---
summary: "NilPy: a missing __add__/__sub__/__mul__/__truediv__/__neg__ ABORTS COMPILATION; CPython raises a catchable TypeError, so try/except around it cannot even build"
type: bug
track: N
prio: 45
---

# Missing arithmetic dunder aborts the build instead of raising

- **Type:** bug (NilPy semantics / diagnostics) — **Track N**
- **Opened:** 2026-08-01, found by auditing every dunder dispatch site while
  landing [[bug-nilpy-comparison-dunders-not-dispatched]].

## The defect

Three arithmetic dispatch sites call the compiler's `Error()` when the class has
no matching dunder:

| site | message |
| --- | --- |
| `compiler/parser.inc:8901` | `class has no __neg__() for unary minus` |
| `compiler/parser.inc:13355` | `class has no __mul__()/__truediv__() for this operator` |
| `compiler/parser.inc:13571` | `class has no __add__()/__sub__() for this operator` |

CPython raises a **runtime** `TypeError` for all of these. So this does not
compile at all under pxx, while CPython prints `caught`:

```python
class C:
    def __init__(self, v): self.v = v
try:
    print(C(1) + C(2))
except TypeError:
    print("caught")
```

A `try/except TypeError` is the *correct* Python way to probe for operator
support, and here it fails at build time — the handler can never run.

## Why this is a known shape, not a new question

The already-landed protocol fixes made exactly this move and recorded why. From
the `__contains__` dispatch (`compiler/pyparser.inc`):

> A genuine RUNTIME error (a `try/except` around this must still compile and run
> its handler), not the compile-time `Error()` a first attempt used here -- that
> aborted the whole compilation instead.

`__contains__`, `__call__`, `__getitem__`/`__setitem__` and (2026-08-01) the
ordering dunders all raise at runtime via `PyNotContainerError` /
`PyNotCallableError` / `PyNoSetitemError` / `PyNotOrderableError`. The three
arithmetic sites above are simply the ones that predate that decision and were
never brought along. **So there is nothing to decide** — the direction is
already settled by the sibling fixes; this is the leftover.

## Fix shape

Mirror the ordering fix exactly: a `PyNotOrderableError`-style helper in
`compiler/builtin/pylib.pas` (or one shared `PyUnsupportedOperandError`),
substituted for the three `Error()` calls, building an `AN_CALL` node with
`ASTLeft = -1`. Note `pylib.pas` is frozen into the pinned stable tree but does
NOT trigger the builtin re-pin rule — the compiler does not `uses` pylib, only
NilPy programs do.

Worth folding into [[feature-nilpy-arithmetic-dunders-full-protocol]] if that is
picked up first, since it touches the same three branches — but it stands alone
and is much smaller.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` per operator whose
output is CPython's own (`caught`, not a build failure) for the missing-dunder
case, and a check that the reflected/present cases are unchanged.
