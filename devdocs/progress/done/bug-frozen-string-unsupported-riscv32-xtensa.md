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

## 2026-07-14 — RECON (no code changed; returned to backlog)

**The ticket's premise is wrong for riscv32, and that makes it much cheaper than filed.**
riscv32 does NOT lack frozen-string branches — it has them, keyed on the pre-b305 predicate
`= tyString`, which misses `tyFixedString` / `tyShortString`. So it IS the b305 widening:

- `compiler/ir_codegen_riscv32.inc:136` — `EmitStrOperandRISCV32`: `operandTk = tyString`
- `:718` and `:1046` — frozen buffer -> managed handle (`PXXStrFromLit(len, buf+8)`)
- `:1641` — external C call passes `buf+8` as `const char*`
- `:1205` — the "frozen concat unsupported" error is also gated on `= tyString`, so a
  fixedstring concat currently slips PAST the error and miscompiles instead of erroring

`PXXWriteFrozenW` (the writeln arm) is already there and already uses
`TypeIsFrozenString` (`:1830`) — which is why `writeln(f)` reaches the right helper while
the assignment that should have filled the buffer did nothing. Widen the four sites above,
then check `Length` (`procIdx = -Ord(tkLength)`, `:1402`) and the frozen arm of IR_STORE_SYM.

Confirmed repro (unchanged): `test/test_frozen_string_cross_b305.pas` on riscv32 prints
`len=0`, an empty string, then SEGFAULTS; x86-64 prints the full expected output.

**xtensa is the one that genuinely has nothing** — 0 `TypeIsFrozenString` sites. That half
is still missing-feature work.

## 2026-07-14 — riscv32 RESOLVED (778cfaed, b345). Ticket rescoped to XTENSA only.

riscv32 output is now byte-identical to the x86-64 oracle, and
`test_frozen_string_cross_b305.pas` is wired into `make test-riscv32` so it cannot regress
silently again. It was BOTH of the things this ticket argued about:

- **the b305 widening after all** — four dispatches still on `= tyString`
  (`EmitStrOperandRISCV32`, the two frozen->managed materialisations, the external-C
  `const char*` adjust, and the "frozen concat unsupported" error, which a fixedstring
  slipped PAST — miscompiling instead of erroring);
- **and genuinely missing paths**, as the ticket said: `IR_STORE_SYM` had no frozen arm at
  all (which is why the buffer stayed empty), `Length` read a heap header at `[handle-8]`
  instead of the buffer prefix at `[buf+0]`, and a frozen buffer passed to a MANAGED string
  parameter went over as if it were a heap handle — the callee read the 8 bytes BEFORE the
  buffer as a length, and that was the segfault.

Ported from aarch64: `EmitFrozenStoreRISCV32` (with an explicit byte-copy loop — no `rep
movsb`), `EmitAnsiStringFromNodeRISCV32`, and aarch64's STRUCTURAL Length predicate (a
frozen operand is not tagged: `f` lowers to an IR_LEA of its symbol, `pf^` to a bare
pointer load).

## What remains: xtensa

`ir_codegen_xtensa.inc` has **zero** `TypeIsFrozenString` sites — nothing to widen, all of
it to write. Port the same three pieces (frozen store, frozen Length, frozen->managed at the
call argument), mirroring the riscv32 shapes now in tree.

Caveat before starting: the xtensa cross leg is currently giving NO signal —
`make test-esp-bare`'s esp32s3 half is red and was already red at 51968776
([[bug-esp32s3-bare-boot-no-uart-output]]). Fix or route around that first, or the work
cannot be verified.

## Log
- 2026-07-14 — resolved, commit 13704303.
