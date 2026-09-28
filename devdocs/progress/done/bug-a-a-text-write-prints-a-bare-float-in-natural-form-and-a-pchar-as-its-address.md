---
track: A
prio: 25
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-28, writing the StdErr separation test; a PChar or an `Output` reference turns StdErr into the Text RTL's variable)
tags: [pascal, text-io, formatting, cross-target, silently-wrong]
summary: "A write through a Text VARIABLE (Output, the Text RTL's StdErr, a real file) printed a float with no decimals in natural form (`2.25`; FPC ` 2.2500000000000000E+000`), a Single the same, `d:12` as padded natural form, and a PChar as its ADDRESS, on every target, x86-64 included. `Str(d:12, s)`, `Str(single, s)` and a variable-width console write (`WriteLn(d:w)`) share the formatter and were wrong too. TextStrArg now sends a float without decimals to StrFloatSciW (FPC's scientific form, narrowed to the width, in the value's own precision) and a PChar through PCharToString."
owner: ""
---

# A Text write prints a bare float in natural form and a PChar as its address

```pascal
{$mode objfpc}
var d: Double; p: PChar;
begin
  d := 2.25; p := 'pchar';
  WriteLn(Output, d);   { pxx: 2.25      FPC:  2.2500000000000000E+000 }
  WriteLn(Output, p);   { pxx: 4243008   FPC: pchar }
end.
```

This happens whenever the Text-file unit is pulled in. Declaring a PChar
variable or naming `Output` does it, and so does any real `Text` file. After
that, `StdErr` is the unit's Text variable rather than the constant, so
`WriteLn(StdErr, d)` takes this path too.

## Cause

Every argument of a Text write is rendered by `TextStrArg`
(pasparser_stmt.inc), and so is `Str`, a variable field width on the console,
and a formatted array-of-const element.

- For a float with no decimals it called `StrFloat(x, width, -1)`: FloatToStr's
  natural form. No FPC write produces that. `Str`'s own comment called it
  "write's default", but FPC's write default is the scientific form, which the
  console path has always printed.
- A PChar is an unsigned pointer to `TypeIsOrdinal`, so it fell into the
  StrQWord arm and printed its address.

## The fix

- A float without decimals goes to `StrFloatSciW(v, width, isSingle)`
  (builtin.pas). It uses SciFormatFor's digit rule (Double 16/3, Single 9/2,
  narrowed to the width, one fractional digit minimum) and PXXWriteFloatSci's
  rounding (PxxSciDigits17, half-up on the integer mantissa), then
  right-justifies. The text is the console writer's.
- A PChar goes through `PCharToString`, then the string arm, padding included.

## Measured (2026-09-28, fixedpoint 9ce84ba69527)

`test/test_text_write_float_and_pchar.pas` writes through `Output`, a Text
StdErr and a real file. It covers bare, negative, zero and negative-zero
Doubles; `d:12`, `d:8` (the clamp) and `d:30`; `d:0:2`; 1.5e300; -3.25e-300;
the smallest subnormal; a 9.999… value that rounds up; a Single bare, `:12` and
`:0:3`; a PChar bare, `:8` and nil; a variable width on the console and on a
Text; and `Str` in four forms.

- Both streams equal FPC 3.2.2's on x86-64, i386, arm32, aarch64, riscv32 and
  xtensa windowed/call0.
- The pinned v450 differs on 10 of the 13 stdout lines.
- Differential over the 885 `test/*.pas` files that name a float type, PChar or
  Text: each was built with v450 and with this compiler, run, and compared. 750
  built with both. 744 stdouts matched; one differs as intended (this test); and 5
  differences are not about formatting: four link errors that print the binary's
  own name, and one random port. The pin could not build 135 others. Of those, the 2 that have a
  `.expected` and build alone match it; the rest have no `.expected` (they are
  refusal tests or are asserted in the Makefile), or need a unit path or
  `--threadsafe` from their Makefile row.

## Not in this fix

On wasm32, EVERY write through the Text RTL, including a plain
`WriteLn(Output, 'x')`, dies with "Runtime error 9 (I/O error)". That is so
with the pinned v450 and with `-Fulib/rtl/platform/wasi` on the path. It has
nothing to do with formatting, so this test has no wasm32 row.
