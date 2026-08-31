---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`bytes.fromhex(\"6162\")` and `float.fromhex(\"0x1p3\")` are `undefined variable (bytes)` / `(float)` — the TYPE used as a namespace resolves only for the handful of names the stdlib table lists (int.from_bytes, dict.fromkeys, str.maketrans)."
---

# The classmethod constructors on builtin types are absent

Found 2026-08-16 by a `tools/pydiff.py` sweep over the builtin surface.

```python
bytes.fromhex("6162")     # CPython b'ab'    pxx: undefined variable (bytes)
float.fromhex("0x1p3")    # CPython 8.0      pxx: undefined variable (float)
int.from_bytes(b, "big")  # works — it is in the table
dict.fromkeys(xs)         # works — it is in the table
str.maketrans("a", "b")   # works — it is in the table
```

So the mechanism exists (`PyStdlibCallProc`'s dotted table) and these two names
are simply not in it. The diagnostic is misleading in a specific way: it says
*"undefined variable (bytes)"*, blaming the TYPE NAME the program used
correctly, and `bytes` IS a working callable one line earlier — see
[[project_nilpy_five_builtin_type_names_are_also_pylib_procs]] for why that
name in particular reads oddly.

`bytes.fromhex` is the one worth having: hex-string-to-bytes is ordinary
protocol and test code. `float.fromhex` is rare.

## Work

Add `bytes.fromhex` (and `float.fromhex`) to the dotted table with pylib
implementations, exactly as `int.from_bytes` is done. Watch the ODD-length and
non-hex cases: CPython raises ValueError, and a silent partial parse would be
the wrong trade.

## Gate

A `.npy` diffed against CPython: even and odd lengths, embedded spaces (CPython
allows them between byte pairs), an invalid digit raising ValueError, and a
user `def fromhex` still shadowing nothing it should not.
