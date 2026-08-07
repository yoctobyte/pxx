---
track: N
prio: 45
type: bug
commit: PENDING-COMMIT
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

## FIXED 2026-08-07 — an ABI lie in the `-> None` arm, not the field registration

The narrowing above pointed at field registration. **It was wrong**, and the
probe that settled it is worth recording because it inverted the conclusion:

```
FAILING (dataclass):  PROBE dataclass field native tk=17 fldSig=1209
WORKING (plain class): (no probe line for `native` at all)
```

The dataclass registers the field **correctly, with a real signature**. The
plain class does not register a field at all — its class-level annotation makes
a CLASS ATTRIBUTE, so `w.native = push1` becomes a per-instance override that
takes the dynamic path. So the "working" row was working by taking a completely
different route, and the properly-registered static call was the broken one.

### The actual cause: the call succeeds and dies RETURNING

```python
@dataclass
class Box:
    fn: Callable[[int], None]
def show(n):
    print("got", n)
Box(show).fn(5)          # prints "got 5", THEN segfaults
```

`got 5` printing is the whole diagnosis: argument marshalling is fine.

`Callable[..., None]` registered its `$proctype` as a **procedure**. That is an
ABI lie — every unannotated NilPy def compiles to a **variant-returning
function** whose result travels through a hidden destination POINTER the callee
copies into unconditionally on the way out. Called through a procedure-typed
signature, that register holds whatever the last call left in it, so the
callee's epilogue writes 16 bytes to a garbage address.

pyeval's `TPyCallFn0..3` already declare around exactly this, with the same
reasoning: *"A `-> None` callee ignores the destination, so declaring it here is
safe for both shapes."* The `Callable` annotation path simply did not follow its
own rule — the comment two lines below the bug already said the declared result
is "a HINT, not an ABI", and the `-> None` arm was the one place that treated it
as one.

Fix: a Callable signature is **always** a variant-returning function.

### Measured

Every dataclass shape now works and matches CPython: through the generated ctor,
without `Optional`, without a default, assigned after construction, a
value-returning Callable field, and two instances keeping their own callables.
Test `test/test_nilpy_callable_field_call_returns.npy`, 7 lines oracle-diffed.

### Residual — a DIFFERENT shape, still failing, pre-existing

A plain (non-dataclass) class with **no class-level annotation**, whose Callable
field is typed only by the constructor parameter, still segfaults — identically
on the pinned binary, so it is untouched by this fix and by the
`Callable`-parameter change of the same day. Repro `fc2`/`fld`: 

```python
class Word:
    def __init__(self, native: Callable[[VM], None]):
        self.native = native
```

That field is registered by the `self.x = …` scan with **fldSig = -1** (seen in
the probe above), so the call has no signature at all. Filed as
[[bug-nilpy-callable-field-typed-only-by-a-ctor-parameter-has-no-signature]].

### uforth is NOT fixed by this

Still segfaults at `uforth.py:840`, same backtrace. Four repros built from that
line's shapes — `Optional[Word]` method call, Callable field call through a
variant receiver, the dataclass field call — all now pass, so uforth's failure
is something else on that line and needs bisecting the RUN rather than guessing
from the source. [[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]] stays
open.

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`
GREEN.
