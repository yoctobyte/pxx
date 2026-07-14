---
summary: "arm32/i386: Int64/QWord -> Double conversion converts only the LOW word — d := int64(1) shl 40 gives 0, silently"
type: bug
prio: 55
---

# arm32 + i386: Int64→Double conversion drops the high word

- **Type:** bug (silent wrong value, both 32-bit hosted targets). **Track A**
  (ir_codegen_arm32.inc, ir_codegen386.inc int→float conversion paths).
- **Status:** backlog
- **Opened:** 2026-07-14 (night session), found while fixing
  [[bug-pascal-qword-to-double-signed]].

## Repro

```pascal
var i: int64; d: double;
begin
  i := int64(1) shl 40;
  d := i;
  writeln(d:0:0);   { FPC/x86-64/aarch64/riscv32: 1099511627776 }
                    { arm32, i386: 0 }
  i := -i;
  d := i;
  writeln(d:0:0);   { -1099511627776; arm32/i386: 0 }
end.
```

The 32-bit backends' int→double conversion (vcvt/cvtsi2sd/fild-style paths and
the IR_STORE float coercions) consume only the low register of the lo:hi pair.
Values that fit 32 bits convert fine, which is why nothing in the suite caught
it. riscv32 is CORRECT (its soft conversion handles the full pair, signed and
unsigned both — verified with 2^63 qwords), so the riscv32 lowering is the
reference for the fix.

QWord (unsigned) sources on these targets additionally need the unsigned
interpretation — fold that in with the same fix
([[bug-pascal-qword-to-double-signed]] covers x86-64/aarch64/riscv32; arm32
and i386 inherit it here). Correct sequence: d = hi * 2^32 + lo(unsigned),
with hi signed for Int64 / unsigned for QWord.

## Acceptance

- Repro matches FPC on arm32 and i386 (qemu).
- test_u64_to_double.pas (added by the qword ticket) extends to arm32/i386
  in the Makefile cross sections.
- tint642.pp's float sections then run correctly on the 32-bit targets too.
