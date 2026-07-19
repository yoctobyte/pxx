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

## Sequencing — and a correction

Bytes are flat ints, not variant slots, so this does NOT wait on
[[bug-a-nilpy-variant-element-not-usable-as-scalar]] or
[[feature-rtti-field-reflection]]. But it is **not purely Track N** either,
which the first draft of this ticket got wrong. Split it:

**Pure Track N — LANDED 2026-07-20 in 6468ff22** (TPyBytes, `bytearray(n)`,
`bytes(b)`, indexing with negative indices, `len`, `test_nilpy_bytes.npy` in
the gate). What follows is what that commit covered:
- TPyBytes in pylib.
- `bytearray(n)` and `bytes(x)` spelled as ordinary pylib FUNCTIONS. Neither
  name is a Pascal keyword, so they resolve through the normal call path with
  no frontend hook at all — the trick that made dict's `.get` work as two
  overloads. (`set()` needed a hook only because `set` IS a keyword.)
- `b[i]` read/write and `len(b)`, via a default indexed property, exactly as
  TPyDict does.

**STILL OPEN — needs a shared-parser (Track A) hook:**
- **Slice syntax** `b[a:c]`, read and assign. The subscript grammar lives in
  `parser.inc`'s index path, which Track N must not edit.
- **`int.to_bytes(n, "little", signed=True)`** — a method call on an int, with
  a KEYWORD argument. NilPy has no keyword arguments at all. Recommend
  recognising these two as intrinsics with a fixed argument shape rather than
  taking on keyword arguments for 36 sites.

Same shape as [[bug-a-nilpy-and-or-in-unavailable-in-call-arguments]]: the
frontend can own the meaning, but the shared parser has to know where the form
is legal.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.
