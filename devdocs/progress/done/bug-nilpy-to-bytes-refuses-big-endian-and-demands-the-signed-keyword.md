---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`(258).to_bytes(2, \"big\")` did not compile: the to_bytes/from_bytes intrinsics REQUIRED a `signed=` keyword and refused every byte order but \"little\". Both are optional in CPython — signed defaults to False, byteorder has defaulted to \"big\" since 3.11 — so ordinary network code was rejected."
---

# `to_bytes` refused big-endian and demanded `signed=`

Found 2026-08-16 by a fresh `tools/pydiff.py` sweep over the builtin surface,
not by a report.

## Measured

```python
(258).to_bytes(2, "big")            # CPython b'\x01\x02'   pxx: compile error
(258).to_bytes(2, "little")         # ok on both
(7).to_bytes()                      # CPython b'\x07'       pxx: compile error
int.from_bytes(b"\x01\x02", "big")  # CPython 258           pxx: compile error
```

The diagnostics were honest — *"only the 'little' byte order is supported"*,
*"needs the signed= keyword argument"* — but they refuse **programs CPython
accepts and runs**, which is the one direction the compatibility promise does
not allow. `signed` defaults to False in CPython and almost nobody writes it;
`byteorder` has defaulted to `"big"` since 3.11; big-endian is *network byte
order*, so the refused half is the half serialization code actually uses.

## Cause

`PyParseByteOrderAndSigned` was written when NilPy had no keyword arguments at
all, and its comment says so: it accepts *"exactly the shape the corpus uses"*.
That was a fair trade for an intrinsic nobody else called, and it stopped being
one as soon as anything but uforth reached for it.

## Fix

- Both tail parts are optional now, with CPython's defaults (`signed=False`,
  `byteorder="big"`, and a bare `to_bytes()` meaning one byte).
- `"big"` is the little-endian image **reversed** — one new pylib routine,
  `pybytes_reversed`, used in both directions (`to_bytes` reverses the result,
  `from_bytes` reverses the input) — rather than a second conversion.
  `normalise-dont-special-case`: the arithmetic stays in one place.
- A byte order that is neither still errors, and so does an unexpected keyword.

## Gate

`test/test_nilpy_to_bytes_byteorder_and_defaults.npy` — thirteen rows across
both orders, both signednesses, the two omitted-argument forms and both
directions, every value CPython's. uforth (whose
`int(v).to_bytes(8, "little", signed=True)` is the shape the old parser was
built for) still compiles and runs. `gate.sh quick` green.
