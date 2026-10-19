---
track: N
prio: 75
type: bug
---

# `int(None)` answers 0 instead of raising TypeError

Found 2026-10-19 compiling sysdash's backend.py (the Vloot fleet monitor's
collector). `int(read(path))` on a root-only RAPL file got `int(None)`, which
answered 0, so the program's `except TypeError` never ran and the native binary
reported a measured 0 J where CPython fell back to the estimate. That's a silent wrong value.

**Cause:** `pyint_v` (compiler/builtin/pylib.pas) handed VT_EMPTY to
`pyvar_to_int`, whose None→0 is the deliberate Optional[int] sentinel for
coercions. An explicit `int()` call is not a coercion.

**Fix:** `pyint_v` raises CPython's TypeError for VT_EMPTY. `pyvar_to_int` is
unchanged, so the sentinel contract that uforth relies on still holds.
`float(None)` already raised.

**Test:** test/test_nilpy_int_of_none_raises.npy (four routes: a variant
parameter, a None return, the literal, a missing dict.get).
