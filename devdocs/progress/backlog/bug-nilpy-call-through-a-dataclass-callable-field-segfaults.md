---
track: N
prio: 45
type: bug
summary: "Calling through a Callable FIELD segfaults when the field belongs to a @dataclass (or is typed only by a ctor parameter). The same field on a plain class with a class-level annotation works. This is what makes uforth segfault at run time."
---

# Calling through a dataclass's `Callable` field segfaults

Minimal repro, 20 lines:

```python
from dataclasses import dataclass
from typing import Callable, Optional

class VM:
    def __init__(self):
        self.n = 0

@dataclass
class Word:
    name: str
    native: Optional[Callable[["VM"], None]] = None

def push1(vm):
    vm.n = vm.n + 1

vm = VM()
w = Word("inc", push1)
print(w.native is not None)   # True — correct, on both
w.native(vm)                  # SIGSEGV
print(vm.n)                   # CPython: 1
```

Storing the callable and testing it against None are **correct**. Only the CALL
through the field faults.

## Pre-existing

Identical on `stable_linux_amd64/default/pinned` — exit 139 after printing
`True` on both. Measured 2026-08-07 after the two uforth compile blockers were
cleared; it is **not** a consequence of those fixes, and not of the
`Callable`-parameter change that landed the same day
([[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]]), which was
controlled against pinned for exactly this shape.

## The discriminator — dataclass vs an explicit ctor

| shape | result |
| --- | --- |
| `@dataclass` with `native: Optional[Callable[...]] = None` | **SIGSEGV** |
| plain class, class-level `native: Optional[Callable[...]] = None`, explicit `__init__` assigning it | **works** |
| plain class, NO class-level annotation, field typed only by the ctor parameter | **SIGSEGV** |
| field assigned directly at module level (`w.native = push1`) | works |

So the field is represented correctly when an explicit class-level annotation on
a NON-dataclass class types it, and wrongly when the type comes via the
(generated or hand-written) constructor parameter. That is the axis to
investigate — not `Optional`, which is present in both the working and failing
rows.

## Why it matters now

**This is what makes uforth segfault.** With the compile blockers gone, uforth
reaches run time and dies at `uforth.py:840`, `if word.is_native():`, where
`Word` is exactly the dataclass above — DWARF backtrace:

```
#0 VM.exec_token_runtime (token="CORE.UFO") at uforth.py:840
#1 VM.exec_token            at uforth.py:1043
#2 VM._interpret_current_source_line at uforth.py:1165
#3 VM.interpret_file (path='STD.UFO')   at uforth.py:1259
#4 load_stdlib_if_any       at uforth.py:4236
```

So it also blocks [[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]] and,
through it, the "uforth still green" gate on
[[bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position]].

## Where to look

`PyWrapClosureFieldCall` is the field-call path and reads the field as a CODE
ADDRESS. Compare what the field's registered type/`UFldProcSig` is in the
working row versus the dataclass row — the working one presumably carries the
`$proctype` signature from the class-level annotation and the failing one does
not, so the call has no signature to marshal against and jumps through whatever
the slot holds. Dump both with `PXXDBG=a.ir:<the calling method>` before
changing anything.

## Gate

Per-fix loop, plus a `.npy` covering all four rows of the table above,
oracle-diffed, and `make test-uforth` getting past `uforth.py:840`.
