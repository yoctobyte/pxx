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

## 2026-08-07 — narrowed to the FIELD REGISTRATION, not the call and not the store

Three more measurements, each removing a candidate:

| variant | result |
| --- | --- |
| dataclass, `Optional[Callable[...]] = None` | SIGSEGV |
| dataclass, **bare** `Callable[...]` (no Optional, no default) | SIGSEGV |
| dataclass, field assigned **after** construction (`w.native = push1`) | SIGSEGV |
| plain class, class-level annotation only, assigned after construction | **works** |
| plain class, class-level annotation + explicit `__init__` | **works** |

So it is **not** `Optional`, **not** the default, **not** the generated
constructor, and **not** the store — assigning the field after construction
fails just the same. The only surviving variable is **which code path registered
the field**.

### The two paths

Both know about this and both look right by inspection, which is why the next
step is to dump and compare rather than read:

- **dataclass** — `pyparser.inc` ~19113: `tk := PyAnnTypeAt(j)` then
  `fldSig := PyAnnLastProcSig` (captured early, deliberately, with a comment
  citing `bug-nilpy-dataclass-callable-field`), and at ~19230
  `LastTypeProcSig := fldSig` immediately before `AddUField`.
- **plain class** — the class-level-annotation registration, which produces a
  working field for the identical annotation text.

`AddUField` takes the signature from the global `LastTypeProcSig`
(`symtab.inc:1021`), and `PyWrapClosureFieldCall` reads `UFldProcSig` to decide
that `w.native(vm)` is an indirect call at all.

**Next step:** print `UFldProcSig` for the field in both shapes — the dataclass
one is almost certainly -1 despite the capture above (so the call has no
signature to marshal against and jumps through the raw slot), and the question
is which of the two assignments to `LastTypeProcSig` is not reaching
`AddUField`. Do not assume the capture works because the code says so; that is
what this narrowing already disproved twice over.

### Parked

Not fixed — the remaining step is a compiler-side print/compare that wants a
fresh session. The narrowing above should make it short: the repro is 20 lines,
the discriminator is one table row, and both candidate sites are named.
