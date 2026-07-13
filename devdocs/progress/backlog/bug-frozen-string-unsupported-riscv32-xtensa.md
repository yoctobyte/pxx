---
prio: 55
---

# bug: frozen inline strings (string[N]) are not implemented on riscv32 / xtensa

- **Track:** A (compiler core — backends)
- **Found:** 2026-07-13, while fixing the same family on aarch64/arm32/i386 (b305, ab568c7c)

## What

`string[N]` (tyFixedString) and shortstring (tyShortString) are frozen inline strings:
a buffer holding `[len:8][chars]`. On riscv32 and xtensa they do not work at all:

```pascal
type TF = string[255];
var f: TF;
begin
  f := 'hello';
  writeln('len=', Length(f));   { riscv32: len=0 }
  writeln('f=', f);             { riscv32: empty }
end.
```

Silently wrong — no error, no crash, just an empty string with length 0.

## Why this is NOT the same fix as b305

On aarch64/arm32/i386 the frozen paths EXISTED and merely tested `= tyString`
instead of `TypeIsFrozenString(...)`, so widening the predicate fixed them
(ab568c7c). riscv32 and xtensa are different: they have **no frozen-string branch
at all**.

- `ir_codegen_riscv32.inc`, `Length` (search `procIdx = -Ord(tkLength)`): the body is
  only the dynamic-array case (`a0 = handle; count at [handle-8]`). There is no
  "frozen inline string -> read the 8-byte prefix at [buffer+0]" arm, which every
  other backend has.
- Neither backend has an `EmitAnsiStringFrom...` / string-parts helper pair, so a
  frozen string handed to a MANAGED string parameter cannot be materialised into a
  heap handle either. (On aarch64 that exact hole was the test_lfm segfault.)

So this is missing feature work, not a one-word predicate widening. Port the aarch64
shape: the frozen arm of IR_STORE_SYM / IR_STORE_MEM, the frozen arm of Length, and a
frozen->managed materialisation helper called from the call-argument loop.

## Repro

`test/test_frozen_string_cross_b305.pas` is the ready-made oracle — it passes on
x86-64, i386, aarch64 and arm32 with identical output. Run it on riscv32 (and on
xtensa via the ESP harness) and make it match:

```
tools/testmgr.py --tier full --job 'test-riscv32#src:test/test_frozen_string_cross_b305.pas'
```

## Note on scope

Whether this matters depends on whether frozen strings reach these targets in
practice — the RTL's TypInfo does use them (interned RTTI names are frozen), so any
riscv32/xtensa program touching RTTI/streaming or TypInfo's enum surface is exposed,
and would fail SILENTLY (empty names, zero lengths) rather than loudly.
