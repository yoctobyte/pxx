---
summary: "NilPy: a missing __add__/__sub__/__mul__/__truediv__/__neg__ ABORTS COMPILATION; CPython raises a catchable TypeError, so try/except around it cannot even build"
type: bug
track: N
prio: 55
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

## 2026-08-01 — measured scale, and a FOURTH site this ticket missed

The CPython differential sweep (1094 cases, binary at `3f2c5b915`) produced 40
compile failures. **36 of them are this defect** — a construct CPython answers
with a catchable `TypeError` that pxx refuses to compile:

| compile error | cases |
| --- | --- |
| `can only concatenate list with another list (+)` | 14 |
| `class has no __mul__()/__truediv__() for this operator` | 13 |
| `class has no __add__()/__sub__() for this operator` | 9 |

The first row is a **site this ticket did not list**: it is not one of the three
dunder-dispatch `Error()` calls, it is pylib's own list-concat type check
(`[1,2] + 3`). Same defect, same fix, different place — so the ticket's original
"three sites" framing was too narrow. Grep for the pattern rather than the three
line numbers: any `Error(...)` reached from a NilPy *expression* whose CPython
answer is an exception is one of these.

The remaining 4 failures are genuinely unimplemented protocols, tracked in
[[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] (`repr`,
`__iter__`/`__next__`, `__getattr__`, `__delitem__`) — not this bug.

### Why the count matters

At 36/40 this is the single largest source of compile-time divergence in the
sweep, and every one of them is a program CPython runs fine. A NilPy program
that probes for operator support the normal Python way — `try: a + b / except
TypeError:` — cannot be built. That is a stronger case for the fix than the
original three-site framing suggested; consider raising `prio` above 45 when
scheduling.

Note this is the *loud* half of the same story as
[[bug-nilpy-static-typed-operands-skip-mixed-type-guard]]: where both operand
types are static, some pairs abort the build (here) and others silently do
pointer math (there). Whichever is picked up first should decide the shared
answer — a runtime `TypeError` raise — so the two do not land inconsistent
behaviour for neighbouring operand pairs.

## FIXED 2026-08-01

`PyUnsupportedOperandError` (`compiler/builtin/pylib.pas`) + `PyMakeUnsupportedOperand`
(`compiler/parser.inc`), replacing the compiler `Error()` at **all four** sites —
including the list-concat one this ticket originally missed:

| site | was |
| --- | --- |
| `parser.inc` `__add__`/`__sub__` dispatch | `class has no __add__()/__sub__()` |
| `parser.inc` `__mul__`/`__truediv__`/`__floordiv__`/`__mod__` dispatch | `class has no __mul__()/...` |
| `parser.inc` `__neg__` (unary minus) | `class has no __neg__()` |
| `parser.inc` list-concat check | `can only concatenate list with another list (+)` |

All four now build an `AN_CALL` to the pylib helper — a genuine runtime
`TypeError`, so `try: a + b / except TypeError:` compiles and runs its handler,
and execution continues past it.

`test/test_nilpy_unsupported_operand_raises.npy` is byte-identical to CPython:
each of the five operator forms caught, the list-concat case caught, execution
CONTINUING afterwards (the whole point of moving these to run time), and a class
that does define the operator still working.

Native confirm: self-host fixedpoint A==B==C from the pinned seed, testmgr
--tier quick GREEN; matrix offloaded to Track T.

### Note on what did NOT change

This makes the diagnostic honest; it does not make the operand pair legal. A
pair Python DOES define but pxx computes wrongly is a different ticket
([[bug-nilpy-static-typed-operands-skip-mixed-type-guard]]) — that one needs a
legality table, whereas this one only needed the existing "no dunder found"
answer routed to a raise instead of an abort.

## Log
- 2026-08-01 — resolved, commit HEAD.
