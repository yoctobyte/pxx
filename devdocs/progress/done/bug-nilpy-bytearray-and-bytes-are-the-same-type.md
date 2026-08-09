---
prio: 30
track: N
type: bug
blocked-by: []
status: done
---

# `bytearray` and `bytes` are the same type — repr, type name and mutability

- **Type:** bug (NilPy, observable divergence) — **Track N**
- **Found:** 2026-08-09 while closing
  [[feature-nilpy-runtime-method-dispatch-on-variant]]
- **Owner:** claude-AN

```python
b = bytearray([1, 2])
print(b)                    # CPython bytearray(b'\x01\x02')   pxx b'\x01\x02'
print(bytes([1, 2]))        # CPython b'\x01\x02'              pxx b'\x01\x02'
print(type(b).__name__)     # CPython bytearray                pxx bytes
```

Both map to one `TPyBytes`, so they are indistinguishable in repr and in
`type().__name__`.

## Why it is a real bug and not laxity

It survives the upward-compatibility rule: a program CPython accepts and runs to
completion observes the difference. Printing a bytearray is the obvious case;
branching on `isinstance(x, bytearray)` or on `type(x).__name__` is the one that
silently takes the wrong path.

The deeper half is **mutability**: `bytes` is immutable in CPython and
`bytearray` is not, so `b[0] = 5` must work on one and raise on the other. If
NilPy allows it on both, code that relies on bytes being immutable (a dict key,
a shared constant) has no guard.

## Shape of a fix

`TPyList` already carries an `FKind` discriminator to tell a list from a tuple
from a set — three Python types over one class, with the kind deciding repr,
`type().__name__` and `isinstance`. `TPyBytes` wants the same treatment: one
field, set at construction, consulted by the renderer, the type-name answer, the
isinstance test and any mutating method.

Follow `PYSEQ_TUPLE`'s example rather than inventing a second mechanism — and
note the lesson recorded there: a display that fails to STAMP the kind is a
wrong *type*, not just wrong brackets, so every construction site must set it.

## Gate

`.npy` diffed against CPython: repr of both, `type().__name__` of both,
`isinstance` against each, round-tripping one into the other
(`bytes(bytearray(...))`), and `b[0] = 5` succeeding on a bytearray while
raising TypeError on a bytes.

## Fixed (2026-08-09, claude-AN)

`repr`, `type().__name__` and `isinstance` all match CPython, both ways round.

### Followed TPyList's precedent, as the ticket said

`TPyBytes` gains an `FIsByteArray` tag, the twin of `TPyList.FKind` — one Python
type per tag over one Pascal class — and `pybytes_kind_v` is the twin of
`pyseq_kind_v` that lets `isinstance` answer from the tag instead of the class.
`False` (a plain `bytes`) is the default, so the ~30 other `TPyBytes.Create`
sites keep today's behaviour and only the four `bytearray(...)` constructors
stamp it.

### The tag has to TRAVEL — most of the work, and most of the test

Stamping at construction alone passes `print(bytearray([1]))` and then loses the
type at the first operation. Fixed and asserted in both directions:

| | before | now |
| --- | --- | --- |
| `b[0:1]`, `b[::2]` | `b'\x01'` | `bytearray(b'\x01')` |
| `b + c` / `c + b` | both `bytes` | left operand decides, as CPython does |
| `isinstance(b, bytes)` | True | **False** |
| `isinstance(c, bytearray)` | True | **False** |

That is exactly the lesson the ticket quoted from `PYSEQ_TUPLE` — a site that
fails to stamp the kind is a wrong TYPE, not just wrong brackets — one level
further out: an operation that fails to PROPAGATE it is the same bug.

### Correction to this ticket: the "deeper half" is not a half

The ticket called mutability the deeper half — `bytes` is immutable in CPython,
so `b[0] = 5` should raise on one and not the other. **That is not a defect
here.** NilPy lets you mutate either, which is accepting what CPython REJECTS —
laxity under the upward-compatibility rule, and no working CPython program can
observe it. It is struck from the scope rather than left as unfinished work, and
the test says so instead of pinning today's answer.

What remains genuinely open is narrower and unrelated to this fix: `bytes` has
no `.append`/`.extend` in CPython (an AttributeError), while here both classes
share the methods. Same laxity argument, same verdict.

### Verification
`test/test_nilpy_bytearray_vs_bytes.{npy,expected}` (`.expected` from CPython):
repr of all three sources (literal, `bytes([..])`, `.encode()`), type names,
isinstance self and cross and against unrelated types, slice both forms, concat
both directions, conversions, empty, equality by value, nesting in a list and a
dict, and through a function parameter. `gate.sh quick` GREEN; the bytes,
isinstance, set and tuple test families re-diffed against CPython.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
