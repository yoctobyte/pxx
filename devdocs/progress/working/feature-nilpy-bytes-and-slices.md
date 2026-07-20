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

**SLICE SYNTAX — LANDED 2026-07-20.** Read and assign, for str, bytes and
list, diffed against CPython in `test/test_nilpy_slices.npy` (now in the
`test-nilpy` gate).

- pylib: `pystr_slice` / `pybytes_slice` / `pylist_slice` / `pybytes_setslice`,
  all sharing one `PySliceBounds` so the three element types cannot drift.
  Python semantics: negative bounds count from the end, bounds CLAMP, an
  inverted range is empty (unlike indexing, which raises). An omitted bound is
  compiled to the `PY_SLICE_OMIT` sentinel — safe precisely because slices
  clamp, so a literal MaxInt already means "the end".
- Bytes slice ASSIGN rejects a length change loudly rather than splicing: a
  quiet resize would move every address above the write and corrupt uforth's
  data space.
- Track A hooks — three sites, all gated on `PyExprMode`, all deciding by the
  same depth-1-colon lookahead (`PySliceBracketAt`), because the default
  indexed-property path consumes the bracket itself: the `ParseFactor` suffix
  wrapper (non-lvalue bases), `ParseLValueAST`'s suffix loop, and
  `ParseClassRecordSelectors` (the `self.memory[a:b]` route). A plain `[i]` is
  untouched on all three. **No grammar conflict:** nothing in the Pascal
  dialect puts a `:` inside brackets (set ranges use `..`).
- A slice is not an lvalue, so assignment is handled by REWRITING the already
  built read call into `pybytes_setslice` — no new AST node. Two statement
  routes needed it: `self.buf[a:b] = x` and the plain-local `buf[a:b] = x`.
- **LANDMINE (cost most of the debugging):** the hooks silently did not fire
  because the bytearray FIELD had no class identity — a separate, pre-existing
  bug where any call returning a class dropped which class. Filed and fixed as
  [[bug-nilpy-call-returning-class-loses-identity]]; it was also segfaulting
  `len(self.memory)` on its own.
- **LANDMINE:** pxx self-host was byte-identical while FPC could not resolve
  the three new pyparser routines called from `parser.inc` — they need
  `forward` declarations there. Invisible to the local gate; caught only by
  `make fpc-check`.

**STILL OPEN — the other half of this ticket:**
- **`int.to_bytes(n, "little", signed=True)` / `int.from_bytes(...)`** — a
  method call on an int, with a KEYWORD argument. NilPy has no keyword
  arguments at all. Recommend recognising these two as intrinsics with a fixed
  argument shape rather than taking on keyword arguments for 36 sites.
  **This is now uforth's wall** (uforth.py:271 parses; it stops on `to_bytes`).

Same shape as [[bug-a-nilpy-and-or-in-unavailable-in-call-arguments]]: the
frontend can own the meaning, but the shared parser has to know where the form
is legal.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.
