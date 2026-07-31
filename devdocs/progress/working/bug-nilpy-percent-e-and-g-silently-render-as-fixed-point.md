---
track: N
prio: 55
type: bug
---

# `%e` and `%g` silently render as `%f` — a wrong answer to an EXPLICITLY requested format

```python
print("%e"   % 1500.0)      # CPython: 1.500000e+03    pxx: 1500.000000
print("%.2e" % 1234.5)      # CPython: 1.23e+03        pxx: 1234.50
print("%g"   % 1500000.0)   # CPython: 1.5e+06         pxx: 1500000.000000
print("%g"   % 0.0001)      # CPython: 0.0001          pxx: 0.000100
```

This is deliberately filed apart from the float-repr tickets, which are low
priority by decision: representation *fidelity* (which digits a bare `print`
chooses) is one thing, but `%e` is the program ASKING for scientific notation
and being handed fixed-point. That is a contract, and the same category as
"provide requested decimals" — which `%f` and `%.15f` already honour correctly.

## Measured

| expression | CPython | pxx |
| --- | --- | --- |
| `"%e" % 1500.0` | `1.500000e+03` | `1500.000000` |
| `"%E" % 1500.0` | `1.500000E+03` | `1500.000000` |
| `"%.2e" % 1234.5` | `1.23e+03` | `1234.50` |
| `"%g" % 1500000.0` | `1.5e+06` | `1500000.000000` |
| `"%g" % 0.0001` | `0.0001` | `0.000100` |
| `f"{x:e}"` | `1.500000e+03` | compile error (loud) ✓ |
| `"%f" / "%.2f" / "%.0f"` | correct | correct ✓ |

The f-string spelling `{x:e}` REFUSES loudly, which is the right failure. Only
the `%` spelling answers with the wrong thing silently.

## Root cause — one case arm

`pylib.pas`, `pypercent_format`:

```pascal
    'f', 'F', 'e', 'E', 'g', 'G':
      begin
        if not hasPrec then prec := 6;
        spec := spec + '.' + pystr_of(Int64(prec)) + 'f';    { <-- always 'f' }
      end;
```

Six conversion characters collapse onto the fixed-point formatter. `e`/`E` and
`g`/`G` were never implemented and were folded in here rather than rejected.

## Shape of a fix

- **`e`/`E`**: mantissa normalised to one leading digit, `prec` fractional
  digits (default 6), then `e`/`E` and a SIGNED, at-least-two-digit exponent.
  `FloatToExpStr` in `compiler/builtin/builtin.pas` already normalises a
  mantissa and pads the exponent to two digits, but it uses its own digit rule
  rather than honouring `prec` — reuse the normalisation, not the digits.
- **`g`/`G`**: C's rule — use `%e` when the exponent is < -4 or >= precision,
  else `%f`, and strip trailing zeros in both.
- If either is not going to be implemented now, they should REFUSE the way
  `{x:e}` already does rather than quietly produce fixed-point.

Watch the interaction with
[[bug-nilpy-float-repr-loses-small-values-and-does-not-round-trip]]: that
ticket's mantissa noise would show up in `%e` output too, but only past the
digits `prec` asks for, so honouring `prec` is independent of it.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
with CPython's own output, and the `%f` rows kept as the guard that the shared
fixed-point path is untouched.

## CLOSED

Implemented as suggested: `PyFmtExp` (mantissa normalised into [1,10) via
FloatToExpStr's own loop, digits via `PyFmtFixed`'s half-up rule so `prec` is
honoured exactly, with a re-normalise step for the 9.9999996-rounds-to-10.xxx
edge) and `PyFmtG` (the C `%g` threshold rule, trailing zeros stripped via two
small split-at-`e` helpers). Both bypass `pyformat_of`'s `{}`-spec grammar
entirely — it has no `e`/`g` kind and correctly refuses `{x:e}` at compile
time — and reuse the same `PyFmtPad` width/zero/align step `%s` already goes
through.

Every row in the ticket's table now matches CPython, plus zero/negative/large-
exponent/explicit-precision cases checked while writing the test. The `%.0f %
1.5` → `1` (CPython: `2`) oddity noticed while testing is NOT this ticket —
confirmed present on the pre-fix binary too, unrelated pre-existing rounding
behavior in `PyFmtFixed` untouched by this change.

Test: test/test_nilpy_percent_e_g_format.npy. Gate: make test-nilpy green,
self-host fixedpoint, testmgr --tier quick.

Ticket closed.
