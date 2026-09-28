---
track: A
prio: 55
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "A float parameter, a float local living across a yield, and a float ELEMENT of a stackless generator all moved through SlSet/SlGet, whose Int64 conversion is numeric. 2.5 arrived as 4612811918334230528.0, a Single local lost its fraction, and a yielded Double came out as its bit pattern (x86-64, aarch64) or as garbage (i386, arm32, riscv32). Every target, Pascal and Nil Python."
owner: ""
---

# A float parameter of a stackless generator arrives as its bit pattern

```pascal
function G(d: Double): Double; generator; stackless;
begin
  WriteLn(d:0:2);   // 4612811918334230528.00
  yield d;          // the loop variable got the bit pattern
end;
```

## Mechanism

A generator instance slot is one Int64 word, written with
`SlSet(g, off, v: Int64)` and read with `SlGet`. A Double stored that way is
converted to an integer on the way in and back on the way out. The caller stored
arguments that way, the step saved and restored locals that way, and the yield
published the element that way.

## Fix

In `pasparser_stmt.inc`, float slots are copied bitwise at their own width
(`SLFloatSlotBytes`: 4 for Single, 8 otherwise):

- `GenSeedArg` seeds a float argument through a temp of the parameter's kind,
  then `SlBlob`. The temp also converts an integer argument, as a plain call would.
- `SLSaveLocals` and `SLRestoreLocals` use `SlBlob` and `SlUnblob`.
- `SLLowerYield` blobs a float element into the CURRENT word, and the `for`
  consumer unblobs it into a temp of the element kind, then assigns.
- Nil Python's `PyBuildGeneratorValue` seeds through `GenSeedArg`.

## Test

`test/test_stackless_float_param_and_element.pas`: a row in `test-core` and rows
in `test-i386`, `test-aarch64` and `test-arm32`. riscv32 was also measured. Measured wrong with pin v446 (`stable_linux_amd64/default/stable_pinned`) on 2026-09-28.
