---
slug: bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32
title: "An Int64 assigned to a Variant loses its high half on i386 and arm32"
track: A
prio: 55
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
summary: "Found while fixing bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical. Boxing a value into a Variant moves only FOUR bytes into the 8-byte payload on the two 32-bit targets, so `v := l` with l: Int64 = -12 makes a Variant holding 4294967284, and `v := 5000000000` holds 705032704. Silent wrong answer, target-dependent, on every operator downstream."
---

# Measured, 2026-08-26, pinned compiler

```pascal
var a: Variant; l: Int64;
begin
  a := 5000000000;  WriteLn(a);   { x86-64 5000000000   i386/arm32 705032704 }
  l := 5000000000;
  a := l;           WriteLn(a);   { x86-64 5000000000   i386/arm32 705032704 }
  a := 3000000000; a := a * 2;
  WriteLn(a);                     { 6000000000 on all four -- see below }
end.
```

| step | x86-64 / aarch64 | i386 / arm32 |
| --- | --- | --- |
| `v := 5000000000` then write | 5000000000 | 705032704 |
| `v := l` (l: Int64) then write | 5000000000 | 705032704 |
| `v := l` with l = -12, then `v or 5` | -11 | 4294967285 |
| a COMPUTED wide result (`v := v * 2`) | 6000000000 | 6000000000 |

The last row is the tell: a result produced by the variant runtime is stored
with a full 8-byte payload and survives, so the slot itself is 16 bytes and the
payload really is an Int64 on every target. Only the BOXING path narrows.

# Root cause

`EmitVariantFill386` (`compiler/ir_codegen386.inc`) is documented as taking
"8 bytes for a double (spilled xmm0), else 4 bytes (eax pushed)". It does
`pop ecx; mov [eax+8], ecx` and then fills `[eax+12]` — with `cdq`'s sign for
VT_INT, with ZERO for every other tag. There is no path by which the high half
of an Int64 operand reaches the payload at all. arm32's twin has the same
shape.

That is the i386 "fat slot" model working as designed for scalars
(`IREmit386CheckScalarSym`: *"the parser still lays out 8-byte slots and i386
code reads/writes only the low 4 bytes"*). A Variant payload is the case where
the high half IS read, so the model's assumption does not hold.

Note the two tags behave differently and BOTH are wrong for a wide value:
VT_INT sign-extends (right for a small negative, wrong above 2^31) and
VT_INT64 zero-fills (wrong for every negative). `a := -12` happens to work
only because the literal boxes as VT_INT.

# The fix

The boxing path must move the whole payload on the 32-bit targets: push the
Int64 operand as a PAIR (the backends already have `EmitBinop64_386`'s edx:eax
convention for exactly this) and store both dwords, the way the double arm
already spills 8 bytes. Then the VT_INT sign-extension arm becomes a
narrow-operand-only case rather than the general one.

`root-cause-over-microfix.md`: vary the shape first — check `var` parameters,
a function result assigned to a Variant, and a record field, not just a plain
assignment.

# Acceptance

- The four rows above answer identically on x86-64, i386, arm32 and aarch64.
- `test/test_variant_bitwise_and_not.pas`'s `agree *` rows load the Variant
  from `l` instead of from a literal, and still pass on all four targets — the
  workaround note in that test's header is deleted when this lands.
- riscv32 is out of scope: it refuses `var_store` outright and has no Variant
  support to truncate.

# Outcome — 2026-08-26

Fixed on both 32-bit targets, and the fix is one rule rather than two patches:
**the high word of a Variant payload comes from the payload's TYPE, not from
the tag.**

## What was wrong

`EmitVariantFill386` and `EmitVariantFillArm32` received a 4-byte payload for
everything that was not a double, and then filled `[slot+12]` by asking whether
the TAG was `VT_INT` — sign-extend if so, zero otherwise. Three cases, two of
them wrong:

| payload | old high word | right answer |
| --- | --- | --- |
| Integer, Int8/16/32 (VT_INT) | sign of the low dword | correct by luck — it IS the sign |
| Int64 / UInt64 (VT_INT64) | zero | the value's own high dword, which was never pushed |
| NativeInt on a 32-bit target (VT_INT64) | zero | the sign of the low dword |
| Boolean, Char, Cardinal, pointer | zero | correct |

`tyNativeInt` is the row that shows the tag was the wrong question all along: it
always FITS in 32 bits there, so nothing was truncated, and it still came out
wrong (`v := n` with n = -12 gave 4294967284) purely because it shares a tag
with Int64.

## The fix

* The boxing sites push the whole value for a 64-bit payload:
  `EmitNode64_386` / `EmitNode64Arm32` — the routines that already exist to
  guarantee a full 64-bit value in `edx:eax` / `r0:r1`, widening a narrow
  source in place — followed by pushing the pair lo-word-last, so the 8 bytes
  at the stack top are the payload in little-endian order, exactly as the float
  spill already leaves them. Both call sites on each target (IR_VAR_STORE and
  IR_VAR_BOX).
* The fill routines gained a 64-bit arm that pops both words, and their narrow
  arm now asks `TypeSigned(payloadTk)` instead of `tag = VT_INT`. That single
  substitution fixes NativeInt and keeps Boolean/Char/Cardinal/pointer exactly
  as they were.

`Is64Bit386` needed a `forward` at the top of `ir_codegen386.inc`: it is
defined below `EmitVariantFill386`, pxx resolves it anyway and the FPC SEED
does not. The gate caught it and named the precedent
(bug-a-fpc-seed-drift-emitasmx64-forward) in the failure text.

## Verification

Thirteen boxing rows and eight shape rows, run on x86-64, i386, arm32 and
aarch64: **all four now produce identical output**, and it matches fpc 3.2.2
-Mobjfpc -O1.

The shapes were varied before closing, as `root-cause-over-microfix.md` asks: a
plain assignment (literal and variable, positive and negative, above and below
2^32), a function result, a `var` parameter, a value parameter, a record field,
an array element, a round trip back out to Int64, arithmetic on the boxed
value, and a comparison. `tyNativeInt` and `Cardinal` cover the two edges of
the signed/unsigned split.

Every other Variant test in `test/` was cross-run on i386, arm32 and aarch64 to
check for collateral: all unchanged.

`tools/gate.sh quick` GREEN; self-host converged after 1 round.

## Found on the way, not fixed here

`RoundTripParam := d` — assigning a Variant to the function result under the
**function-name spelling** — does not convert at all; it stores the variant
slot's ADDRESS. `Result := d`, the same line in the other spelling, converts
correctly. Wrong on EVERY target including x86-64, for Int64, Double and
AnsiString results alike, and measured against fpc 3.2.2, which gets all six
rows right. Filed as
[[bug-p-a-variant-assigned-to-the-result-by-function-name-is-not-converted]];
the new test routes through a local and says why.

Also seen and left alone: `test_variant_record_tag_padding`'s `nested-overlay`
row fails on i386 and arm32 (13/14 there, 14/14 on aarch64). That is a record
VARIANT-PART overlay, a different mechanism from the Variant TYPE payload this
ticket is about, and it fails identically before and after this change.

## Not in scope

riscv32: it refuses `var_store` in IR codegen outright, so it has no Variant
support to truncate. xtensa likewise.

## Files

* `compiler/ir_codegen386.inc` — `Is64Bit386` forward; `EmitVariantFill386`
  keyed off the payload type with a 64-bit arm; both boxing sites push the pair.
* `compiler/ir_codegen_arm32.inc` — the same three changes for `r0:r1`.
* `test/test_wide_int_boxes_into_a_variant.pas` — new, 21 rows.
* `test/test_variant_bitwise_and_not.pas` — its agreement rows now load the
  Variant from an Int64 VARIABLE (they were routed around this bug when it was
  still open), and two boxed-wide rows added.
* `Makefile` — the new test wired into `test-core`.

## Log
- 2026-08-26 — resolved, commit 223e3d981.
