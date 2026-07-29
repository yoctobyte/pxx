---
track: N
prio: 70
type: bug
---

# `str()` of a float whose integer part exceeds Int64 writes garbage bytes

```python
print(1e19)     # CPython: 1e+19    pxx: 9223372036854775809.o72036854775808
print(1e300)    # CPython: 1e+300   pxx: 9223372036854775809.o72036854775808
```

The output is not merely mis-formatted: it contains a literal `o` where a digit
belongs, and the digits after the point are a fragment of the saturated Int64
(`9223372036854775808`) that precedes them. That is a buffer being written past
its end / read back unterminated, in the float→string path — a memory bug that
happens to surface as text.

It is reachable from ordinary arithmetic, not just from a literal: `3 / 0`
yields the same string (see
[[bug-nilpy-runtime-raised-errors-bypass-try-except]]), so any program that divides
by zero prints corrupted bytes to stdout.

The conversion clearly saturates the integer part at `High(Int64)` and then
formats the remainder from the same buffer. It needs the large-magnitude case
handled properly instead — which is also the point at which CPython switches to
exponent form.

## Two more float-formatting divergences from the same sweep

Lower severity — no memory involved, but they make NilPy output differ from the
oracle on ordinary values:

| expression | CPython | pxx |
| --- | --- | --- |
| `1.5e18` | `1.5e+18` | `1500000000000000000.0` |
| `123456789012345678.0` | `1.2345678901234568e+17` | `123456789012345680.0` |
| `0.1 + 0.2` | `0.30000000000000004` | `0.3` |
| `"%e" % 3.14159` | `3.141590e+00` | `3.141590` |

(`%e` was the ONLY divergence in a 21-case sweep of f-strings, `%`-formatting
and `.format()` — everything else matched CPython exactly, so it is a
one-conversion gap, not a formatting-engine problem.)

CPython's `repr` is the SHORTEST string that round-trips, in exponent form
outside `1e-4 .. 1e16`. pxx prints a fixed-point form with fewer digits, so
`0.1 + 0.2 == 0.3` is False while the printed forms are equal — the classic
confusing-output case. Whether to match CPython exactly here is worth deciding
once (it affects every printed float); the garbage-byte case above is a bug
regardless.

## Gate

`make test-nilpy` + self-host byte-identical, plus a float-printing regression
table diffed against CPython.

## PARTIALLY RESOLVED — `str()` is exact; `print()` is a separate path

`str(1e19)` now yields `1e+19`, matching CPython exactly. So does `1e+300`,
`-1e+19`, and the same through a variable.

### What produced the invalid byte

`compiler/builtin/builtin.pas`, `FloatToStr`: `intpart := Trunc(v)` SATURATES
at High(Int64) past 2^63, and every digit below is then derived from the
saturated value — `d` leaves 0..9 and `Chr(Ord('0') + d)` emits a byte that is
not a digit. That is the `o` in `9223372036854775809.o72036854775808`.

Fixed by handling the three cases the Int64 split cannot represent, before it
runs: NaN, ±Inf, and |v| > 9.2e18 → a new `FloatToExpStr`, which normalises the
mantissa into [1,10) and formats it with FloatToStr itself (in range by
construction, so there is one formatting rule rather than two). The mantissa
drops a trailing `.0` and the exponent is padded to two digits, so the result
reads `1e+19` the way Python writes it rather than `1.0E+19`.

The same three guards went into `lib/rtl/sysutils.pas`'s `FloatToStr` and
`FloatToStrF`, which had the identical saturation.

### The residue: `print()` does not use FloatToStr

`print(1e19)` still prints the garbage, because a float argument to print goes
to the BACKEND float writer (`EmitWriteFloatNat`, hand-written per target), not
through pystr_of. So `print(x)` and `print(str(x))` disagree — which Python
never does.

The hook is identified: pyparser.inc, `PyParsePrint`, at the line
`CurASTNode := PyReprContainer(CurASTNode);` — wrapping a tyDouble/tySingle
argument in the `pystr_of` Double overload there would route print through the
same formatter `str()` uses, fix the garbage on every target at once, and make
the two agree by construction. That is the better fix than repairing
EmitWriteFloatNat in six backends. Filed as
[[bug-nilpy-print-of-a-float-bypasses-str-formatting]].

The remaining formatting divergences (`1.5e18` printed in full, `0.1 + 0.2`
short by a digit, `%e`, `1e-20` printing `0.0`) are unchanged and stay in this
ticket — they are cosmetic, not corrupt.

### Gate — and the re-pin this needed

First `tools/gate.sh full` came back RED on ONE step: `self-host fixedpoint`.
Everything else passed, including `make test`'s own self-host.

Not a regression. `tools/gate.sh`'s fixedpoint seeds from the PINNED binary,
and `make pin` FREEZES `compiler/builtin/*.pas` into
`stable_linux_amd64/default/builtin/` — the pinned compiler resolves
`uses builtin` from that frozen copy, in preference to the live tree
([[project_pinned_stable_builtin_isolation_fix]]). So stage A linked the OLD
builtin and stages B and C the new one: A != B, but B == C, i.e. the fixedpoint
converges one generation later. `make test`'s self-host seeds from the CURRENT
compiler and passed on the first generation, which is what confirms the reading.

Any change to `compiler/builtin/**` therefore needs `make stabilize` + `make pin`
(host only, per [[feedback_pin_host_only_fast_roundtrips]]) and the refreshed
`stable_linux_amd64/**` committed with it. None of tonight's earlier fixes hit
this: `pylib.pas` is also frozen there, but the compiler itself does not `use`
it, so only a `builtin.pas` change moves the seed.

## Log
- 2026-07-30 — resolved, commit 1c8d09b71.
