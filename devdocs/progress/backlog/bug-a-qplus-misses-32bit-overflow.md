---
track: A
prio: 60
type: bug
---

# `{$Q+}` does not trap 32-bit overflow — only 64-bit ops are checked

Found while building [[feature-a-promoint-stage2-storage-arith]] 2026-07-20.
Pre-existing and independent of that work: it affects ordinary Pascal.

## Repro

```pascal
{$Q+}
program p;
var c: Integer;
begin
  c := 2000000000;
  c := c + 2000000000;
  Writeln(c);
end.
```

pxx prints `-294967296` and exits 0. FPC with `{$Q+}` raises `EIntOverflow`
(runtime error 215). The same program with `c: Int64` and a 64-bit-overflowing
value DOES trap in pxx, so the check exists — it just does not cover ops whose
result type is 32-bit or narrower.

## Why it matters beyond the obvious

`{$Q+}` is the switch a user reaches for precisely because they do not trust a
computation to stay in range. Silently honouring it for `Int64` and silently
ignoring it for `Integer` is worse than not having it: the program looks
guarded and is not. Integer is also the DEFAULT integer type, so the unchecked
case is the common one.

It also blocks a feature. `PromoInt32` — the promotable int's 32-bit storage
class, and the one that matters for ESP/riscv32/xtensa where NilPy on ESP is a
project subgoal — cannot trap in its own width without this. It is currently
declaration-blocked with a diagnostic pointing here, and promo arithmetic is
forced to the 64-bit class as a result. Landing this unblocks the honest
per-target storage class.

## Shape

The overflow check is emitted in the `IR_BINOP` path when `ival = 1` (see the
`ASTQChk` site in `ir.inc` and the per-backend `PXXOverflow` calls, e.g.
`ir_codegen386.inc` and `ir_codegen_riscv32.inc`). Establish first whether the
32-bit case is: (a) never tagged with `ival = 1` by the parser, (b) tagged but
skipped in codegen, or (c) emitted with a 64-bit-width test that a 32-bit
wrap slips through. Measure before fixing — do not assume (c).

Applies to `+`, `-`, `*` on all narrower-than-64 ordinal result types, not just
`Integer`.

## Gate

A `{$Q+}` test per width (Integer, Cardinal, SmallInt, Byte) asserting runtime
error 215, plus the existing 64-bit case still trapping and `{$Q-}` still
wrapping. `--tier quick` + self-host byte-identical; cross where a backend's
check is touched.
