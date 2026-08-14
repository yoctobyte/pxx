---
track: A
prio: 30
type: compat
blocked-by: []
summary: "WriteLn/Str of a Single print the value's full Double expansion — 17 significant digits and a 3-digit exponent — where FPC prints 10 digits and a 2-digit exponent: pxx ' 1.0000000149011612E-001' vs FPC ' 1.000000015E-01'. Same class as the FloatToStr(Single) bug fixed in lib/rtl, but this path is the compiler's own float writer, so the RTL cannot reach it. Text-only divergence, no wrong value."
---

# `WriteLn`/`Str` of a `Single` use Double width

- **Type:** compat (FPC parity, text form) — **Track A** (the float writer
  `WriteLn`/`Str` lower to, in `compiler/builtin/**`; the RTL has no way in).
- Filed by Track B on 2026-08-14 alongside
  [[bug-b-floattostr-of-a-single-prints-15-digits-where-fpc-prints-10]], which
  is the same defect in the half Track B owns and is **fixed**. This is the
  half that is not ours.
- **Prio 30, not 60:** the value is right, only its spelling is wider than it
  should be. Contrast
  [[bug-a-a-single-in-array-of-const-is-boxed-4-bytes-and-read-as-8]], found in
  the same sweep, which returns a number unrelated to the argument.

## Measured — pxx vs FPC 3.2.2

```pascal
var s: Single; d: Double; st: ShortString;
begin
  s := 0.1;
  WriteLn(s);            Str(s, st); WriteLn(st);
  s := 1.0/3.0;
  WriteLn(s);
  d := 0.1;
  WriteLn(d);            Str(d, st); WriteLn(st);
end.
```

| | pxx | FPC |
| --- | --- | --- |
| `WriteLn(Single 0.1)` | ` 1.0000000149011612E-001` | ` 1.000000015E-01` |
| `Str(Single 0.1)` | ` 1.0000000149011612E-001` | ` 1.000000015E-01` |
| `WriteLn(Single 1/3)` | ` 3.3333334326744080E-001` | ` 3.333333433E-01` |
| `WriteLn(Double 0.1)` | ` 1.0000000000000001E-001` | *(same)* |
| `Str(Double 0.1)` | ` 1.0000000000000001E-001` | *(same)* |

The Double rows agree exactly, so the writer itself is right — it is the
**width** that is lost. Two things differ together, and one parameter explains
both: FPC renders a Single with **10 significant digits and a 2-digit
exponent**, a Double with 17 and a 3-digit exponent.

`WriteLn(s:0:2)` and `Str(s:0:4, st)` agree with FPC already — an explicit
width bypasses the default entirely, which is further evidence the defect is
only in the default digit count.

## Why it is worth fixing even though no value is wrong

Printing `1.0000000149011612E-001` claims seventeen digits of a value that has
about seven. It is the machine-readable shape of "this is more precise than it
is", and any recorded expectation or diffed output containing a Single is
different from FPC's for a reason that is not the program's.

## The fix, and the reference implementation to copy

`lib/rtl/sysutils` already solved the same problem the same day: it now declares
two overloads and passes a different significant-digit count to one shared
formatter.

```pascal
function FloatToStr(value: Double): AnsiString;   { FloatToStrSig(value, 15) }
function FloatToStr(value: Single): AnsiString;   { FloatToStrSig(value, 10) }
```

The write path needs the equivalent: keep the argument's static type through the
`WriteLn`/`Str` lowering instead of widening to Double first, and select the
digit count (and exponent width) from it. Establish the exponent-digit rule by
measurement against FPC — it is stated above from a two-value sample, not from
FPC's source.

## Sweep before closing

`Write` as well as `WriteLn`; `Str` with and without width/precision; a Single
**field**, array element and function result, not just a variable; and text-file
output as well as stdout. Also `Extended`, which is aliased to Double here and
so should keep the 17-digit form.

## Gate

The table above matches FPC on every row, the Double rows are unchanged, `make
test` + self-host fixedpoint, and cross — the float writer is per-backend, so a
cross check is not optional here.
