---
track: N
prio: 55
type: bug
---

# NilPy: a call returning a CLASS lost its class identity (silent, then SIGSEGV)

Found 2026-07-20 while wiring slices ([[feature-nilpy-bytes-and-slices]]) — the
slice hook would not fire on `self.memory[a:b]` because the field had no class
identity. That turned out to be the symptom, not the cause.

## Symptom

```python
class VM:
    def __init__(self) -> None:
        self.memory = bytearray(16)
        self.memory[0] = 65
    def show(self) -> None:
        print(self.memory[0])     # 65 — correct
        print(len(self.memory))   # SIGSEGV
```

`self.memory[0]` read back correctly, so the field looked fine. `len()` on it
segfaulted: with no class identity the overload set picked `len(const s:
AnsiString)` over `len(b: TPyBytes)` and read a class pointer as a string
handle. Exactly the failure the str-method branches of `PyInferExprType`
already carry comments about — a third instance of the same family.

## Root cause

`PyInferExprType`'s plain-function-call branch (pyparser.inc) typed the call
from `Procs[procIdx].RetType` but never recorded WHICH class when that type was
`tyClass`:

```pascal
procIdx := FindProc(name);
if procIdx >= 0 then tk := Procs[procIdx].RetType;   { class identity dropped }
```

So the class field pre-pass got `tk = tyClass` with `PyInferLastCi = -1` and
stored the field with `fldRec = REC_NONE`. Every consumer that resolves a
record from the field — overload resolution, the default indexed property, the
new slice hook — then saw REC_NONE.

Affects any NilPy field or local inferred from a pylib function returning a
class: `bytearray()`, `bytes()`, and the same shape for lists/dicts.

## Sibling bug fixed in the same sweep

The method-call branch DID record a class, but assigned a **rec id** into
`PyInferLastCi`, which is a **class index**:

```pascal
if tk = tyClass then PyInferLastCi := ProcRetRecId[UMthProc_[si]];
```

Consumers then add `REC_UCLASS_BASE` a second time. Both branches now convert
explicitly (`- REC_UCLASS_BASE`).

## Fix

pyparser.inc, both branches of `PyInferExprType`: record the returned class as
a class INDEX. Landed with the slice work.

## Gate

`make test-nilpy` green (incl. the new `test_nilpy_slices.npy`), `--tier quick`
GREEN, self-host byte-identical. FPC-clean relative to HEAD (the 6 open
`pyparser.inc` FPC errors are the pre-existing fpc-bootstrap regression,
verified identical on committed HEAD).
