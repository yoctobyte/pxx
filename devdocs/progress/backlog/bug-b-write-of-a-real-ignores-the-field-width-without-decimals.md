---
summary: "write(r:W) with a width but no decimals ignores W entirely — pxx always prints the full 16-decimal scientific form where FPC sizes the mantissa to the field"
type: bug
prio: 20
track: B
---

# `write(r:W)` ignores the field width when no decimals are given

- **Type:** bug (Write formatting — mechanical, low prio per the float-handling
  rule). Owning lane B (runtime formatting), but the emitter is compiler ground:
  `EmitWriteFloatSci` (`compiler/symtab.inc:7359`, plus the per-backend siblings
  e.g. `EmitWriteFloatSciA64`) takes **no width argument at all**, and
  `IR_WRITE` in `compiler/ir_codegen.inc:4710` drops `wid` on that path.
  A `compiler/builtin` change needs `make stabilize-fast && make pin`.
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (Write
  formatting topic). The `:W:D` fixed path is fine — `EmitWriteFloatFixed(wid,
  decs)` honours both — and so is every integer/string/char/boolean width. Only
  the real-with-width-but-no-decimals form is wrong.

## Symptom

```pascal
var d: double; begin d := 1.5; writeln(d:5, '|') end.
```

| | output |
| --- | --- |
| FPC | ` 1.5E+000\|` |
| pxx | ` 1.5000000000000000E+000\|` |

pxx prints the identical 22-char string for every width from `:1` to `:26`; the
field is neither shrunk nor padded.

## FPC's rule (measured, `double` and `single` variables)

Scientific form is `<sign><digit>.<decimals>E<expsign><expdigits>`, where the
exponent field is **3** digits for `double`, **2** for `single`, **4** for
`extended` (an untyped real *constant* passed straight to `write` is extended,
which is why a literal probe shows 4 — use variables when checking this).

Decimals are chosen from the requested width and clamped to the type's
precision:

- `double`: `decimals = clamp(W - 8, 1, 16)` — so `W <= 9` gives the minimum
  form `1.5E+000` (9 chars incl. the leading sign position), `W = 17` gives
  `1.500000000E+000`, `W >= 25` saturates at 16 decimals and **pads on the
  left** (`W = 26` -> two leading spaces).
- `single`: `decimals = clamp(W - 7, 1, 7)` — minimum ` 1.5E+00` at `W <= 8`,
  saturating at 7 decimals by `W = 14`.

The exponent grows past its type width when the value needs it (`1e-300` ->
`E-300` in a double's 3-digit field is exact; a 4-digit exponent appears for
extended).

## Fix sketch

Give `EmitWriteFloatSci` the width the way `EmitWriteFloatFixed` already has it:
thread `wid` through `IR_WRITE`, derive the decimal count with the clamp above
from the value's float kind, and left-pad to `W`. Six backends have their own
copy of this emitter — grep `WriteFloatSci` and fix them together, or the
divergence just moves to the cross targets (`devdocs/dev/normalise-dont-special-case.md`).

## Gate

A probe sweeping `writeln(d:i)` for `i` in 1..26 against `fpc -O- -Mobjfpc`,
for `single` and `double`, matches byte for byte; `gate.sh quick` GREEN. Add it
as `test/test_write_real_width.pas` with FPC's output as `.expected`.

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.
