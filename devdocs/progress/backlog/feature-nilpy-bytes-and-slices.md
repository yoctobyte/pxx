---
track: N
prio: 55
type: feature
---

# NilPy: bytearray + slices (uforth's memory emulation)

Hangs off [[feature-nilpy-corpus-uforth]]. Found 2026-07-19 by driving
uforth.py past the dict/set/defaults walls with a stub-and-continue probe.

## The walls, in the order the probe hit them

```
uforth.py:267  undefined variable (bytearray)
                   self.memory = bytearray(1024 * 1024)
uforth.py:271  "memory": no such member on this record/class
                   self.memory[SYS_BASE_ADDR:SYS_BASE_ADDR + 8] = (10).to_bytes(...)
uforth.py:272  expected expression        (int.to_bytes keyword args)
```

## Census in uforth.py

| construct | sites |
| --- | --- |
| slice `[a:b]` (read and assign) | 99 |
| `to_bytes` / `from_bytes` | 36 |
| `bytearray` | 7 |

This is not incidental usage: `vm.memory` IS the Forth data space, and every
`!`/`@` word goes through a slice of it.

## Shape

- **TPyBytes** in pylib — a flat growable byte block, NOT a variant-slot
  list. `bytearray(n)` allocates n zero bytes. Indexing yields an int.
- **Slices**: `b[a:c]` read, and `b[a:c] = value` assign. Assignment of a
  bytes-like of the SAME length is what uforth does everywhere; a
  length-changing splice is a separate, harder case — check the corpus before
  paying for it.
- **`int.to_bytes(n, "little", signed=...)` / `int.from_bytes(...)`**. These
  carry KEYWORD arguments (`signed=True`), which NilPy does not have at all —
  either keyword args land first, or these two are recognised as intrinsics
  with a fixed argument shape. Recommend the intrinsic route: 36 sites, one
  spelling, and keyword arguments are a much larger language feature to take
  on for it.

## Sequencing

Independent of the Track A blockers ([[bug-a-nilpy-variant-element-not-usable-as-scalar]],
[[feature-rtti-field-reflection]]) because bytes are flat ints, not variant
slots — which makes this one of the few uforth-blocking features Track N can
land on its own.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.
