---
track: N
prio: 40
type: bug
summary: "A Callable field on a plain class with no class-level annotation — typed only by the ctor parameter that assigns it — is registered with fldSig = -1, so calling through it segfaults"
status: done
owner: claude-AN
---

# A Callable field typed only by a ctor parameter carries no signature

```python
from typing import Callable

class VM:
    def __init__(self):
        self.n = 0

class Word:
    def __init__(self, native: Callable[[VM], None]):
        self.native = native            # no class-level annotation

def push1(vm):
    vm.n = vm.n + 1

vm = VM()
w = Word(push1)
w.native(vm)                            # SIGSEGV
print(vm.n)                             # CPython: 1
```

## Pre-existing, and NOT the dataclass bug

Identical on `stable_linux_amd64/default/pinned`. Split out of
[[bug-nilpy-call-through-a-dataclass-callable-field-segfaults]], which was a
different cause (a `-> None` `$proctype` registered as a procedure, an ABI lie
that crashed on return) and is fixed — the dataclass shapes all pass now while
this one still fails.

## Cause, already measured

A probe on the two field-registration sites showed:

```
PROBE selfassign field <name> tk=… fldSig=-1
```

The `self.x = …` scan (`pyparser.inc` ~19717) registers the field from the
ASSIGNMENT, and the procedural signature it would need lives on the ctor
PARAMETER's annotation, which that scan does not consult. So `UFldProcSig` is
-1, `PyWrapClosureFieldCall` has no signature to marshal against, and the call
jumps through the raw slot.

Give a class-level annotation and it works — but requiring one is not the fix;
CPython needs no such thing.

## Shape of a fix

When the `self.x = <param>` scan registers a field whose right-hand side is a
PARAMETER carrying a `$proctype` (the parameter annotation recorded one), carry
that signature onto the field, the way the dataclass site already carries
`PyAnnLastProcSig`. The two sites are ~500 lines apart and each knows half the
answer — worth checking whether they should share one helper rather than growing
a third copy.

## Gate

Per-fix loop, plus the repro above added to
`test/test_nilpy_callable_field_call_returns.npy` (which currently covers only
the dataclass shapes), oracle-diffed.


## FIXED 2026-08-07 — and the cause in this ticket was WRONG: it was MY regression

The ticket says the field is registered with `fldSig = -1` because the
`self.x = …` scan does not consult the parameter's annotation. **Measured, and
that is false.** A probe on that exact site:

```
PROBE hdrparam rhs=native tk=17 sig=1211
```

`PyHeaderParamType` already reads the parameter's annotation and the site
already captures `PyAnnLastProcSig` — the field gets a real signature. The
recorded cause was inferred from an earlier probe that happened to show a
DIFFERENT field (`self.n = 0`, an int, legitimately -1).

### What it actually was

A regression from [[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]],
landed the same day. That change gave a `Callable[...]` PARAMETER the VARIANT
ABI so a bound method could travel through one. `PyHeaderParamType` — which
types a FIELD from such a parameter — was not told, and kept answering
tyPointer. So `self.native = native` stored a **variant's tag word into a
pointer slot**, and the later call jumped through it.

**It hid because it was masked.** The `-> None` procedure-ABI bug
([[bug-nilpy-call-through-a-dataclass-callable-field-segfaults]]) crashed this
shape too, on the pinned binary as well — so when it was controlled against
pinned it looked pre-existing and was split out as a separate ticket. Only
fixing the ABI bug unmasked it, and the A/B that proved it was disabling the
parameter change alone and watching both repros go green.

Worth keeping: **a control against PINNED does not prove a bug is not yours when
two causes produce the same symptom.** The pinned comparison was run correctly
and still gave the wrong answer.

### Fix

`PyHeaderParamType` reads the annotation under `PyAnnParamScope`, so a field
typed from a parameter agrees with the parameter's real ABI. One line, plus the
note explaining why it must stay in step.

### Measured

Ten Callable-field shapes now pass, all oracle-diffed: dataclass (through the
generated ctor, without Optional, without a default, assigned afterwards,
value-returning), plain class with a class-level annotation, plain class typed
ONLY by the ctor parameter, two callables on one instance, a variant receiver,
and `Optional[Word]` method calls. The bound-method-through-a-Callable-parameter
fix that started this is intact (`mat` repro, all six rows).

Test: `test/test_nilpy_callable_field_call_returns.npy`, 10 lines byte-identical
to the CPython oracle.

### uforth still segfaults

Same place, `uforth.py:840`. Every Callable-field shape derived from that line
now passes, so it is something else there.

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`
GREEN.

## Log
- 2026-08-07 — resolved, commit 8e432cf50.
