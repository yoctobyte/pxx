---
prio: 55
track: N
type: bug
blocked-by: []
status: done
---

# `s.split(None)` does not split — the whole string comes back as one field

- **Type:** bug (NilPy; valid CPython, silently wrong answer) — **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a text-wrapping utility that
  used `line.split(None, 1)` to peel the first word).

```python
s = "a b  c d"
s.split()            # ['a', 'b', 'c', 'd']   — always worked
s.split(None)        # CPython ['a','b','c','d'];  pxx ['a b  c d']
s.split(None, 1)     # CPython ['a', 'b  c d'];    pxx ['a b  c d']
s.rsplit(None, 1)    # CPython ['a b  c', 'd'];    pxx ['a b  c d']
```

Silent: a wrong split still answers a list of strings, so the caller keeps
going with one field where it expected several.

## Cause

CPython's signature is `split(sep=None, maxsplit=-1)` — **None IS the default
separator**, not a degenerate one. `PyStrMethodFinish` routed by ARITY alone, so
one explicit argument always meant `pystr_split_sep`, and the None was coerced
to a string separator that matches nothing.

## Fix

Two parts, both needed — the arity table cannot express this on its own:

- `PyArgIsNoneLiteral` recognises the None **literal** (a no-argument `pynone`
  call, what `PyMakeNone` builds) as the first argument of `split`/`rsplit`, and
  drops it from the chain so the existing no-separator arity logic applies. It
  matches the VALUE, not the spelling: `s.split(sep)` where `sep` happens to
  hold None is a run-time fact and is left alone.
- `split(None, maxsplit)` has no separator-based equivalent — the separator is a
  whitespace RUN of any width, leading whitespace is skipped rather than
  producing an empty first field, and an all-whitespace remainder contributes no
  field at all. So `pystr_split_ws_max` / `pystr_rsplit_ws_max` join pylib
  beside `pystr_split_ws`.

`pylib.pas` is a NilPy PROGRAM's runtime and the compiler does not `use` it, so
this needs no re-pin to gate (see the scope note on
[[project_builtin_change_needs_repin_for_gate_fixedpoint]]); a pin is still what
carries the new runtime to `$(PXX_STABLE)` consumers.

## Verified

`test/test_nilpy_split_none_separator.npy` — 19 rows (every maxsplit including
0 and -1, both directions, leading/trailing whitespace, all-whitespace and empty
receivers, plus the exact-separator forms as controls) diff clean against
`.expected`, which is CPython's own output.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
