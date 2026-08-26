---
slug: bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32
title: "An Int64 assigned to a Variant loses its high half on i386 and arm32"
track: A
prio: 55
type: bug
blocked-by: []
status: backlog_new
owner: ""
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
