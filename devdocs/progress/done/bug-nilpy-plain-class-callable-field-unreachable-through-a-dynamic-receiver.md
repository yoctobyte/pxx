---
track: N
prio: 35
type: bug
summary: "A plain class's `Callable` field records no signature, so `def run(o): o.native(x)` on a dynamically-typed receiver is a COMPILE ERROR (\"no class declares a method or callable field\") — only a @dataclass field is reachable that way"
status: done
---

# A plain-class Callable field is unreachable through a dynamic receiver

```python
from typing import Optional, Callable

class PC:
    native: Optional[Callable[[int], None]] = None
    def __init__(self, name, native=None):
        self.name = name
        self.native = native

def plain(k):
    print("plain", k)

def run(o):          # o is dynamically typed
    o.native(3)      # error: no class declares a method or callable field .native()

run(PC("x", plain))  # CPython: plain 3
```

The identical program with `PC` as a `@dataclass` compiles and runs.

## Cause

`pyparser.inc`'s dynamic-receiver scan (the `hitCi < 0` fallback in the member
path, ~line 9427) recognises a callable field by `UFldProcSig[mmi] >= 0`. Only
the **@dataclass field registration** records a signature; a plain class's field
is typed either from the `__init__` parameter it is assigned from or from a
class-level annotation, and neither writes `UFldProcSig`. So the scan finds
nothing and errors.

Moving the annotation ABOVE `__init__` does not help — measured.

## PARTLY PRE-EXISTING — corrected 2026-08-08

Reproduced identically under `stable_linux_amd64/default/pinned` — but ONLY for
the shape written above, where the class carries a class-level
`native: Optional[Callable[...]] = None` annotation ALONGSIDE the ctor
parameter.

**CORRECTION:** the commoner shape — a field typed purely from an annotated
`__init__` parameter, with no class-level annotation — runs FINE under `pinned`.
For that one the compile failure was a regression from
[[bug-nilpy-closure-stored-in-a-callable-field-jumps-through-the-variant-tag]]
(mine, same day), not a pre-existing gap. Both are fixed by the second scan pass
described in
[[regression-test-nilpy-test-nilpy-function-values]]; this ticket is closed with
it. That ticket's 16-cell matrix passes because it
calls through a STATICALLY typed local; this is the dynamic-receiver arm.

## Shape of the fix

`UFldProcSig` is doing double duty — ABI (now dead for NilPy, since the slot is
a variant) and "is this field callable". The second job wants its own answer.
Either record the signature for a plain class's `Callable`-annotated field too,
or let the scan accept a `tyVariant` field — the call now dispatches through
`pyvar_callv<n>`, which tells all four callable shapes apart at runtime, so it
does not need the signature to lower correctly.

Accepting ANY variant field would weaken the typo diagnostic (`o.typo(3)` would
resolve to any class with a variant field of that name), so weigh that; and see
[[bug-nilpy-dynamic-receiver-callable-field-casts-to-the-wrong-class]], which
the same scan already has and which more candidates would make worse.

## Gate

The repro above oracle-diffed with `tools/pydiff.py`, the existing
`test_nilpy_callable_field_all_shapes.npy` still green, plus the per-fix loop.

## Log
- 2026-08-08 — resolved, commit ed6e77bbf.
