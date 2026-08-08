---
track: N
prio: 40
type: bug
summary: "SILENT->CRASH: with two classes declaring the same field name, a call through a dynamically-typed receiver hard-casts to whichever class the scan found FIRST — the field offset is read from the wrong layout, no diagnostic"
---

# A dynamic receiver's field call casts to the wrong class

```python
from dataclasses import dataclass
from typing import Optional, Callable

@dataclass
class DC:
    name: str
    native: Optional[Callable[[int], None]] = None

class PC:
    def __init__(self, name, native=None):
        self.name = name
        self.native = native

def plain(k):
    print("plain", k)

o = DC("a", plain)
o.native(1)          # CPython: plain 1
o = PC("b", plain)
o.native(2)          # CPython: plain 2  --  pxx: SIGSEGV
```

Both classes declare `native`. The local `o` holds a `DC` and then a `PC`, so
it is a variant and the call takes the dynamic-receiver path.

## Cause

`PyMakeVariantFieldCall` unboxes the receiver with `pyvarobj` and **hard-casts
it to `hitCi`** — the one class the name scan settled on. The field OFFSET is
then resolved against that class's layout. When the value is actually an
instance of the other class, the read lands at the wrong offset.

The scan's ambiguity check does not catch it: it errors only when the two
candidates' `UFldProcSig` values DIFFER. Two classes can agree on the signature
(or both record none) and still lay the field out at different offsets, which is
exactly the case above — and a signature was never a statement about layout.

Same hazard exists in the sibling METHOD scan, which already has a proper
runtime-dispatch arm (`dualCis`, an `is`-test on the receiver's real class,
feature-nilpy-runtime-method-dispatch-on-variant). The FIELD path never got one.

## PRE-EXISTING, not a regression

Reproduced under `stable_linux_amd64/default/pinned`. Found while gating
[[bug-nilpy-closure-stored-in-a-callable-field-jumps-through-the-variant-tag]] —
that change makes the one-class form work where pinned crashed, so it narrows
this rather than causing it, but it does not touch the multi-candidate case.

## Shape of the fix

Give the field path the runtime dispatch the method path already has: keep the
extra candidates and branch on the receiver's actual class before reading the
field, instead of casting to the first hit. Failing that, the ambiguity error
must key on the field's declaring class rather than on its signature — a wrong
answer with no diagnostic is worse than a refusal.

See also [[bug-nilpy-plain-class-callable-field-unreachable-through-a-dynamic-receiver]];
widening what the scan accepts makes this ticket's blast radius larger, so the
two want deciding together.

## Gate

The repro above oracle-diffed with `tools/pydiff.py`, plus a positive case
proving the correct class is still reached, plus the per-fix loop.
