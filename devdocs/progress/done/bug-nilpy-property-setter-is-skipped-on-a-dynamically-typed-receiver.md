---
track: N
prio: 55
type: bug
summary: "SILENT DATA LOSS: `v.prop = x` where `v` is a dynamically-typed parameter DROPS THE STORE ENTIRELY — the @property setter is never called and nothing is written, with no diagnostic. The identical store on a statically-typed local works. This is what stops uforth loading STD.UFO."
status: done
owner: claude-N
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

## RESOLVED 2026-08-08 — the reported bug was one of THREE, and not the deepest

The dynamic receiver was the symptom that got filed. Narrowing it against the
CPython oracle turned up two more silent property-write losses in the same
concept, one of which is the actual reason uforth still failed after the first
fix was in and measured working.

### 1. A dynamic receiver never reached the property machinery — `parser.inc`

`ParseLValueAST`'s variant-receiver branch resolved a member by FIELD name only
(`PyMakeVariantField`), and a property has no field, so the access fell through
to the dynamic-attribute store: the write landed in pydynattr's side table while
the getter went on reading the backing field. New `PyMakeVariantPropRecv`
(pyparser.inc) unboxes the slot and hard-casts it to the declaring class, and
control then FALLS THROUGH to the class-typed property path — deliberately not a
second implementation, since a second one is what this bug is. Candidate choice
mirrors the method scan: a base and its subclasses are not ambiguous (a virtual
accessor still dispatches), two unrelated classes are a diagnostic rather than a
guess.

### 2. `if not self.prop:` declared a phantom FIELD that shadowed the property

**This is what kept uforth broken after fix 1.** The member pre-pass reads
`self.NAME :` as an annotated field declaration — but the colon that ENDS a
compound-statement header has the same three tokens before it, so `if not
self.compiling:` declared a variant field named `compiling` on the class that
also declares the property. Harmless for a real field (already registered, the
duplicate guard skips it); fatal for a property, which it then shadowed
everywhere. `while self.x:`, `{self.x: 1}` and `a[self.x:]` are the same shape.
An annotated declaration is a STATEMENT, so the scan now requires the `self` to
START one. The `self.x = ...` arm is untouched (chained assignment would break).

This one is why the ticket's own repro was not enough: it had no `self.prop`
read inside a method, so fix 1 made it pass while uforth — which has three —
stayed exactly as broken. **The repro that passes is not the program that
fails**; PXXDBG on `AddUField` is what closed the gap, after reading the source
had not.

### 3. `obj.prop += 1` was dropped on EVERY receiver, static included

Found by the four-shape gate matrix, not by the ticket. The property path tested
only for `:=`, so an augmented assignment took the READ arm: the getter ran, its
RESULT was handed to the assignment machinery, and the store went nowhere.
Desugared to `set(get() OP rhs)` through the property's own accessors, so an
override still dispatches through the VMT. Field-backed and indexed properties
keep their existing paths (the first is already correct; the second would
evaluate the index twice).

## Verified

`test/test_nilpy_property.npy` EXTENDED rather than duplicated — it already
existed and covered only the statically-typed receiver. Now 8 lines across
static receiver, untyped parameter, variant local, list element, dict value,
subclass, augmented assignment on both receiver kinds, the `if not self.prop:`
shadow trigger, and a genuine `self.depth: int = 3` proving the narrowed scan
still registers what it is for. Gated by `.expected` diff instead of the inline
printf.

It DISCRIMINATES — `stable_linux_amd64/default/pinned` fails 4 of the 8 lines:

```
-static aug 22                              +static aug 2
-param compile True 31 True [True]          +param interpret False 10 False []
-listelem 7 7 compile compile               +listelem 7 7 interpret interpret
-dictval 5 5                                +dictval 5 10
```

`make compiler/pascal26` byte-identical (converged in 1 round) ·
`tools/gate.sh quick` GREEN.

## uforth: advanced again, still red, new blocker

`vm.compiling = True` now takes effect and colon definitions compile instead of
executing. `make test-uforth` fails further on, in a different component:
`pyeval: host method define_word has an unsupported param shape` — filed as
[[bug-nilpy-pyeval-host-call-refuses-a-mixed-variant-and-scalar-param-shape]],
which [[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]] now blocks on.

## Log
- 2026-08-08 — resolved, commit bd43aef64.
