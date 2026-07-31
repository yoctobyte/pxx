---
track: N
prio: 35
type: feature
blocked-by: []
---

# bin()/oct() missing; enumerate(xs, start) had no offset form

Found by proactive CPython-diff sweeping. `hex(n)` existed but its siblings
`bin(n)`/`oct(n)` did not (`undefined variable`). `enumerate(xs)` as a value
existed but only ever counted from 0 — CPython's `enumerate(xs, start)` /
`enumerate(xs, start=N)` offset form was unimplemented (parse error: the
for-header-only special case in `compiler/pyparser.inc` and the value-form
special case in `compiler/parser.inc` both only accepted one argument).

## Fix

- `compiler/builtin/pylib.pas`: `oct`/`bin` mirroring `hex`'s convention
  (0o/0b prefix, leading `-` for a negative magnitude, `0o0`/`0b0` for zero).
  Added `pyenumerate2(a: TPyList; start: Integer): TPyList`, same pairs as
  `pyenumerate` with the index offset by `start`.
- `compiler/parser.inc`: the `enumerate(xs)`-as-a-value branch in `ParseFactor`
  now accepts an optional second argument, either positional
  (`enumerate(xs, N)`) or the `start=N` keyword spelling, dispatching to
  `pyenumerate2` when present.

While writing `pyenumerate2`, found `pair.append(start + i)` (a `const
Variant` param on `TPyList.append`) failed to parse OUTSIDE NilPy source —
filed separately as
`bug-a-const-variant-arg-expression-fails-outside-pyexprmode` (a real, general
parser gap, not touched here — worked around locally with a local variable).

Regression test `test/test_nilpy_bin_oct_enumerate_start.npy` (gated in
`test-nilpy`), diffed directly against CPython's own output. Self-host
confirmed byte-identical via `make pxx-debug`.

## Log
- 2026-07-31 — resolved, commit HEAD.
