---
track: B
prio: 40
type: bug
owner: track-b-bughunt
blocked-by: []
summary: "lib/rtl/sysutils declared only FloatToStr(Double), so a Single widened into it and printed its full Double expansion — FloatToStr(Single(0.1)) gave 0.100000001490116 where FPC gives 0.1000000015. The digit count also sets the exponent threshold, so Single(1e10) printed 10000000000 where FPC gives 1E10. Fixed by declaring the width family FPC declares, 15 digits for Double and 10 for Single."
status: done
---

# `FloatToStr` of a `Single` prints 15 significant digits, not FPC's 10

- **Type:** bug (wrong output) — **Track B** (`lib/rtl/sysutils.pas`).
- Found 2026-08-14 by an FPC differential sweep of the sysutils surface — 60
  rows of `Copy`/`Pos`/`Trim`/`StringReplace`/`StrToInt*`/`Format`/`FloatToStr`
  edges, of which this was the only pxx-side divergence.

## Measured — pxx vs FPC 3.2.2

| | before | FPC |
| --- | --- | --- |
| `FloatToStr(Single(1/3))` | 0.333333343267441 | **0.3333333433** |
| `FloatToStr(Single(0.1))` | 0.100000001490116 | **0.1000000015** |
| `FloatToStr(Single(1234.5678))` | 1234.56774902344 | **1234.567749** |
| `FloatToStr(Single(pi))` | 3.14159274101257 | **3.141592741** |
| `FloatToStr(Single(1e-10))` | 1.00000001335143E-10 | **1.000000013E-10** |
| `FloatToStr(Single(1e20))` | 1.00000002004088E20 | **1.00000002E20** |
| `FloatToStr(Single(123456.789))` | 123456.7890625 | **123456.7891** |
| `FloatToStr(Single(1e10))` | 10000000000 | **1E10** |

Every Double row already agreed.

## Cause

One declaration:

```pascal
function FloatToStr(value: Double): AnsiString;   { = FloatToStrSig(value, 15) }
```

so a `Single` widened into it and got Double's 15 significant digits — printing
the exact Double expansion of a value that carries about seven. FPC declares the
family and gives a Single **10**.

The last row is the same parameter, not a separate bug: 10000000000 needs 11
significant digits, so at 10 the formatter switches to the exponent form and
prints `1E10`, which is what FPC does. One number explains both symptoms.

## The fix

Declare what FPC declares, and reuse the formatter that already takes a digit
count:

```pascal
function FloatToStr(value: Double): AnsiString; overload;   { FloatToStrSig(value, 15) }
function FloatToStr(value: Single): AnsiString; overload;   { FloatToStrSig(value, 10) }
```

`FloatToStrSig` existed already for `Format`'s `%.Ng`, so the change is one
overload and no new formatting logic. **10 is measured, not derived** — the
table above is the evidence, and this note exists because "a Single carries ~7
digits" would have suggested 7 and been wrong.

Overload selection was checked rather than assumed: unlike the integer
overloads, where pxx widens to the widest candidate unless the type NAME matches
exactly ([[compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload]]),
a `Single` argument does select the `Single` spelling here. All eight rows now
match FPC.

## Same class, NOT ours — filed separately

The sweep that found this found the same width loss on two paths Track B cannot
reach, and one of them is much worse:

- [[bug-a-a-single-in-array-of-const-is-boxed-4-bytes-and-read-as-8]] —
  `Format('%g', [aSingle])` returns **5.122630465115234E-315**. The compiler
  boxes the element in a `Single`-width local, tags it `vtExtended`, and the RTL
  dereferences 8 bytes. Confirmed arithmetically: that is exactly Single(0.1)'s
  bit pattern read as the low half of a double. Silent garbage, prio 60.
- [[compat-pascal-writeln-of-a-single-uses-double-width]] — `WriteLn`/`Str` of a
  Single print 17 digits and a 3-digit exponent where FPC prints 10 and 2. The
  compiler's own float writer, so the RTL has no way in.

## An FPC-side divergence where pxx is RIGHT — do not chase it

The sweep also turned up `d := 1.0/3.0` (d: Double) printing
`0.333333343267441` under **FPC** and `0.333333333333333` under pxx. That is
FPC folding the constant division at *Single* precision: its runtime `a/b` and
its explicitly-cast `Double(1.0)/Double(3.0)` both give the correct Double, and
pxx gives the correct Double in all three spellings. Recorded here so a later
sweep does not read it as a pxx defect and "fix" it.

## Gate

The table above matches FPC (8 Single rows plus 5 Double rows unchanged), and
`make lib-test` green.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
