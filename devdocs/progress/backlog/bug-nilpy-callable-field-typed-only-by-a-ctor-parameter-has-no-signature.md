---
track: N
prio: 40
type: bug
summary: "A Callable field on a plain class with no class-level annotation — typed only by the ctor parameter that assigns it — is registered with fldSig = -1, so calling through it segfaults"
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
