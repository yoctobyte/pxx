---
track: N
prio: 40
type: bug
summary: "SILENT->CRASH: with two classes declaring the same field name, a call through a dynamically-typed receiver hard-casts to whichever class the scan found FIRST — the field offset is read from the wrong layout, no diagnostic"
status: done
owner: claude-N
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

## RESOLVED 2026-08-08 — and the repro I filed it with was the WRONG shape

Fixed as described: `PyMakeVariantFieldCall` now decides the class at RUN TIME.
It collects every class declaring the name as a callable field (a recorded
signature, or a variant slot), parses the argument list ONCE, and builds one
`pyvarobj(v) is C ? <call as C> : ...` arm per candidate — the same dispatch the
sibling METHOD path uses (`dualCis`) and that `PyMakeVariantField` already uses
for READS whose candidates disagree. The last candidate stays the fallback arm,
so a receiver of none of them behaves as before rather than becoming a new
error. One candidate emits exactly what it used to.

### The repro on this ticket does NOT exercise this path — corrected

Measured with a `PXXDBG` probe on the candidate scan: the two-classes-one-local
program I filed (`o = DC(...)` then `o = PC(...)`) never reaches
`PyMakeVariantFieldCall` at all. `PXXDBG=n.locals` says why — `o` is
**tk=6 (tyClass), rec=1**: a single STATIC class, not a variant. Reassigning a
local across two unrelated classes keeps ONE class identity, and both member
accesses use that layout, so the first call mis-casts. Different bug, different
layer; filed as
[[bug-nilpy-local-reassigned-across-classes-keeps-one-static-class]].

I nearly shipped this fix untested on the strength of that repro. The probe is
what caught it: the new multi-arm code was UNEXERCISED by every test I had
(`nc=1` everywhere). The shape that does reach it is a container element:

```python
for x in [DC("a", one), PC("b", "z", two)]:   # differing layouts
    x.native(7)
```

A/B against MY OWN change — forcing the old single-arm path — segfaults after
the first element; with the fix both dispatch correctly.

`test/test_nilpy_variant_field_call_runtime_dispatch.npy` (new). The layouts are
deliberately different (one field before `native` vs two); with matching layouts
the bug hides, which is how it survived.

`tools/gate.sh quick` GREEN, self-host byte-identical, `make test-uforth` PASS,
and the four sibling callable-field tests re-run clean.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
