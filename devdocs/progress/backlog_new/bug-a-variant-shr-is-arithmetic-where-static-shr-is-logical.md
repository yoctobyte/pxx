---
slug: bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical
title: "`shr` on a negative Variant is an arithmetic shift; on a negative Integer it is logical"
track: A
prio: 50
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Re-filed from decide-variant-bitwise-width, decided 2026-08-25 (option 2). pxx's static Pascal `shr` is a 64-bit LOGICAL shift on both Integer and Int64; its Variant `shr` is a 64-bit ARITHMETIC shift. Two different operators under one spelling inside one language. Fix: Pascal's Variant path emits a logical shift; NilPy keeps the arithmetic one (Python's >> sign-extends), split at the PyProgramMode seam that already exists."
---

# Measured, pinned compiler, 2026-08-25

```pascal
var i: Integer; l: Int64;
begin i := -12; l := -12;
  WriteLn(i shr 1);   { pxx 9223372036854775802   fpc 2147483642 }
  WriteLn(l shr 1);   { pxx 9223372036854775802   fpc 9223372036854775802 }
end.
```

and, from [[decide-variant-bitwise-width]]:

```pascal
var a: Variant; begin a := -12; WriteLn(a shr 1); { pxx -6   fpc 2147483642 } end.
```

| operand | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `Integer(-12) shr 1` | 9223372036854775802 | 2147483642 |
| `Int64(-12) shr 1` | 9223372036854775802 | 9223372036854775802 |
| `Variant(-12) shr 1` | **-6** | 2147483642 |

pxx's static path is 64-bit logical on both widths. Its Variant path is
arithmetic. **The bug is the disagreement with ourselves**, not the disagreement
with FPC — FPC is internally consistent here (logical `shr` at the operand's
declared width; a Variant small int is 32-bit `varInteger`).

# The fix

Pascal's Variant bitwise lowering emits a **logical** 64-bit shift. On x86-64
that is one byte in `EmitVarBinOp` (`sar` → `shr`); the runtime twin was
deliberately made to match the inline path, so both move together — do not fix
one and leave the other, that pairing is why they could not drift before.

NilPy keeps the arithmetic shift: Python's `>>` sign-extends and NilPy is
correct today. The split goes at the lowering seam that already exists for
exactly this (`PyProgramMode` selects the helper).
`the-substrate-is-ast-and-ir-not-the-parser.md`: *"Normalise within a language,
duplicate across languages."*

# Scope — the sibling operators

`root-cause-over-microfix.md` says vary the shape before fixing. The same
question settles `and` / `or` / `xor` / `shl` on a Variant: all 64-bit, all
matching the static path. Check each before closing, on **both** the inline
x86-64 path and the runtime helper.

FPC's 32-bit narrowing is a *behaviour*, not a bug, so if a corpus ever needs it
its home is `--strict-fpc` — not the default. Nothing needs it today.

# Acceptance

- `Variant(-12) shr 1` equals `Int64(-12) shr 1` on every target.
- The same for `shl`, `and`, `or`, `xor` with a negative operand.
- NilPy `-12 >> 1` still answers `-6`.
- `test/test_variant_bitwise_and_not.pas`'s "not covered" note is rewritten to
  assert static/variant agreement instead of recording its absence.
