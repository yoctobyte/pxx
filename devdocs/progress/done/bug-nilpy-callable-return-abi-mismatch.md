---
summary: "nilpy: a def passed to a Callable[...] parameter marshalled by the ANNOTATION, not by the def"
type: bug
track: N
prio: 75
---

# The function-object ABI

- **Type:** bug (Nil-Python frontend, function values) — **Track N**
- **Found:** 2026-07-27 (songformatter key_analysis.py).
- **Class:** segfault, and silently wrong arguments.

## Repro

```python
from typing import Callable
NOTES = {"C": ["C", "E", "G"]}
def notes_of(ch):                 # unannotated -> infers a VARIANT result
    return NOTES.get(ch, [])
def run(f: Callable[[str], list[str]]) -> int:
    return len(f("C"))
print(run(notes_of))              # pxx: SIGSEGV      CPython: 3
```

## Cause

`Callable[[str], list[str]]` registered a `$proctype` whose result is a class
(register return) and whose parameter is a string (by value). The def that
arrives is compiled from its OWN inference: a variant result (hidden-destination
convention) and an unannotated, i.e. variant, by-reference parameter. The
indirect call therefore passed a string where the callee dereferenced a variant
address, and left the hidden destination register holding whatever was there
— the callee wrote its result variant through it.

The declared types cannot be authoritative: one signature marshals calls to
whatever def is handed in, and Python does not check annotations either.

## Fix

One function-object ABI on both ends — variant parameters, variant result:

- `PyAnnTypeAt`'s `callable` branch registers the signature that way (the
  annotation is kept as a hint for readers, and `-> None` still means a proc).
- `PyParseDefHeader` gives the same shape to any def the module also mentions
  as a VALUE (`PyDefUsedAsValue`: a bare name that is not a call, not the `def`
  line, not an attribute).

## Gate

`test/test_nilpy_fnvalue_abi.npy` (in `make test-nilpy`), self-host
byte-identical, `tools/gate.sh quick`.
