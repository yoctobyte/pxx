---
track: P
prio: 60
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "SILENT, i386/arm32/riscv32 only. A LongWord against a signed operand compared in 32-bit signed registers: `c > si` with c = 3000000000, si = -1 was FALSE (FPC TRUE), `$FFFFFFFF = -1` TRUE, `c > -1` FALSE. And QWord against Int64 compared UNSIGNED there (`q > n` with n = -1 FALSE) where x86-64, aarch64 and FPC compare signed. v446 (ae3466a018d8): 15 of 18 fixture rows and 7 of test_compare_mixed_signedness's 28 wrong on each 32-bit target."
---

# A LongWord against a signed operand compares 32-bit signed on 32-bit targets

Found by the Pascal cross-target differential: test_compare_mixed_signedness,
green natively, failed 7 of 28 on i386, arm32 and riscv32.

## Resolution (2026-09-28)

Two halves of one rule. TypeCompareUnsigned answers SIGNED for a 4-byte
unsigned operand against a signed one (FPC widens the pair to Int64), noting
"values are still evaluated in 64-bit registers" -- true on x86-64 and aarch64
only. On the 32-bit targets the pair stayed in 32-bit registers.

- pasparser_expr (the comparison arm): on a 32-bit target, a LongWord or
  NativeUInt against a signed operand narrower than 8 bytes is widened on both
  sides to Int64, as `Int64(c) > Int64(si)` spells it (already right there).
- symtab TypeBinop64Unsigned: the 32-bit pair path took a comparison's
  signedness from the arithmetic rule ("a QWord is present"); a comparison of
  two ordinal operands now asks TypeCompareUnsigned, the rule x86-64 and
  aarch64 use.

Fixture `test/test_a_longword_against_a_signed_operand_compares_in_int64.pas`
(.expected by FPC 3.2.2), and test_compare_mixed_signedness now cross too, in
test-core for i386/aarch64/arm32/riscv32.
