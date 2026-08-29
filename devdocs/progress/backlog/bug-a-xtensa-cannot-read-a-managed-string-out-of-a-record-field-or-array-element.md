---
track: A+S
type: bug
prio: 45
status: open
found: 2026-08-30
found-by: frankS
---

# Reading an AnsiString out of a record field or array element is broken on xtensa

Storing a managed string into an aggregate and reading it back gives garbage.
riscv32 and x86-64 are both correct; this is xtensa-only.

## Repro

`--target=xtensa --platform=posix --xtensa-soft-mulhigh`, Call0, qemu-xtensa.

```pascal
program t; type R = record f: AnsiString; end;
var r: R; begin r.f := 'ABCDE'; WriteLn(r.f); end.
{ x86-64: ABCDE    riscv32: ABCDE    xtensa: <empty line> }

program t; var a: array[0..2] of AnsiString;
begin a[1] := 'ABCDE'; WriteLn(a[1]); end.
{ x86-64: ABCDE    riscv32: ABCDE    xtensa: <empty line> }

program t; type R = record f: AnsiString; end;
var r: R; begin r.f := 'ABCDE'; WriteLn(Length(r.f)); end.
{ x86-64: 5        riscv32: 5        xtensa: 1936482630 }
```

## It is NOT a `Length` bug, and that is the useful part

The obvious reading of the third case is that `Length` mishandles a field
operand — it is the one that looks like the arm-specific defects fixed in
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]]. It is
not. Copying the field to a plain local first:

```pascal
r.f := 'ABCDE'; x := r.f; WriteLn(Length(x));   { xtensa: 1936482630 }
```

is wrong the same way, and `WriteLn(r.f)` — no `Length` anywhere — prints
nothing. **The value read out of the aggregate is already wrong before anything
is done with it.** Suspect the field/element load or store of a `tyAnsiString`,
not the consumers.

`1936482630` is `$736F5F46`, bytes `46 5F 6F 73` = `"F_os"` — a pointer into
rodata or a fragment of one, not a heap handle and not a length. Whatever the
load produces, it is not the handle that was stored.

## Where to start

`IR_FIELD` on xtensa is `IREmitNodeXtensa(base)` plus a constant add — it yields
an ADDRESS and never derefs, which matches riscv32. So the divergence is more
likely in the managed store (`store_mem` of a tyAnsiString through a field
address, including whether it retains) or in the load position that follows it.
Compare against riscv32's `IR_STORE_MEM`/`IR_LOAD_MEM` handling for
`tyAnsiString` rather than against its `IR_FIELD`, which is the same.

## Scope

Blocks at least `test_cross_managed_aggregate_locals` and
`test_cross_openarray_string` in
[[bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs]], and is a
plausible cause for the two interface tests there (an interface's fields are the
same shape). Filed separately from that ticket because it has a single crisp
repro and they do not.

## Bound

Object-level plus observable output, hosted profile, Call0, at `3bc9a9303267`,
compared directly against riscv32 and x86-64 built from the same source.
Windowed not checked — it faults earlier for unrelated reasons
([[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]]).
