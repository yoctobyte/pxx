---
track: N
prio: 55
type: bug
summary: "SILENT DATA LOSS: `v.prop = x` where `v` is a dynamically-typed parameter DROPS THE STORE ENTIRELY — the @property setter is never called and nothing is written, with no diagnostic. The identical store on a statically-typed local works. This is what stops uforth loading STD.UFO."
---

# A @property setter is skipped when the receiver is dynamically typed

25-line repro — line 2 agrees with CPython, line 3 does not:

```python
class VM:
    def __init__(self):
        self._c = False
        self.log = []

    @property
    def compiling(self) -> bool:
        return self._c

    @compiling.setter
    def compiling(self, value: bool) -> None:
        self._c = value
        self.log.append(value)

vm = VM()
print("start", vm.compiling)
vm.compiling = True
print("after direct", vm.compiling, vm._c, vm.log)   # both: True True [True]

def setit(v):            # v is dynamically typed
    v.compiling = True

vm2 = VM()
setit(vm2)
print("after fn", vm2.compiling, vm2._c, vm2.log)
#   CPython: True True [True]
#   pxx    : False False []
```

`_c` is untouched and `log` is empty, so the setter did not merely write the
wrong place — **the store vanished**. No warning, no error. The getter still
works on both paths, which is what makes it look like a read bug.

## Two paths, one concept — the usual shape

The property-setter store is implemented on the STATICALLY-typed receiver path
only. A receiver whose class the frontend has not resolved (a plain `def f(v)`
parameter, a variant slot, a container element) takes the other path, which
stores a plain field — and for a property there is no such field, so the write
goes nowhere. Compare
[[project_nilpy_lvalue_vs_selector_path_must_both_know]]-style splits: teach one
member-access path and the sibling stays broken.

Note the ASYMMETRY: the getter is honoured on the dynamic path, the setter is
not. That is what makes the failure read as "the flag never got set" rather than
"the store was dropped".

## PRE-EXISTING

Reproduced identically under `stable_linux_amd64/default/pinned`. Nothing to do
with the Callable-field or `-> None` ABI work of 2026-08-08; it was simply
unreachable in uforth until the segfault ahead of it was cleared.

## This is what blocks uforth

`uforth.py` maps its Forth `STATE` flag onto memory through exactly this
pattern:

```python
@property
def compiling(self) -> bool: return self._compiling
@compiling.setter
def compiling(self, value: bool) -> None:
    self._compiling = value
    self.memory[SYS_STATE_ADDR:SYS_STATE_ADDR + 8] = ...
```

`w_colon` (the `:` word) is a lifted nested def taking `vm` as a normalised
VARIANT parameter, so its `vm.compiling = True` is dropped. Every colon
definition therefore stays in interpret mode and its body EXECUTES instead of
compiling. Observable at uforth's own prompt:

```
: X 1 ; 5 X .        CPython: 1        pxx: 5     (X's body is empty)
.S                   CPython: <empty>  pxx: 13 junk entries — the PYTHON word
                                       bodies from CORE.UFO, pushed as literals
```

and `STD.UFO` dies at `CORE.UFO:80` with "expected a number, got str", which is
the RTL coercing one of those stray strings. One cause, all three symptoms.

## Gate

The repro above oracle-diffed with `tools/pydiff.py`, extended to cover the
other dynamic receivers (variant local, list element, `self` inside a method
reached as a bound value), plus `make test-uforth` getting past `STD.UFO`, plus
the per-fix loop. A property setter that cannot be reached should be a
DIAGNOSTIC, never a dropped store — if some receiver shape genuinely cannot
dispatch it, say so at compile time.
