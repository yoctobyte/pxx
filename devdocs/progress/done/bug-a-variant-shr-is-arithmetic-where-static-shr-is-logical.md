---
slug: bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical
title: "`shr` on a negative Variant is an arithmetic shift; on a negative Integer it is logical"
track: A
prio: 50
type: bug
blocked-by: []
status: done
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

# Outcome — 2026-08-26

Fixed on every target that has Variants at all, and the sibling sweep the
ticket asked for turned up one operator, not five.

## What was actually wrong, and where

**Measured first.** `shl`, `and`, `or` and `xor` on a negative Variant already
agreed with the static operator on all four targets — only `shr` disagreed, so
the fix is one operator wide, not a family.

The split is made where the ticket said it should be, at the seam that already
carries the string rule:

* **x86-64** hand-emits the shift in `EmitVarBinOp` (`compiler/ir_codegen.inc`).
  Both arms — the integer-integer one and the float-operand one that rounds
  through `cvtsd2si` — now emit `shr rax,cl` (`48 D3 E8`) for Pascal and keep
  `sar rax,cl` (`48 D3 F8`) for NilPy, chosen off `PyProgramMode`, the same
  flag `pasPlus` two hundred lines above already uses. Fixing only one of the
  two arms would have made `v(-12.4) shr 1` disagree with `v(-12) shr 1`.
* **every other target** calls the runtime. `PXXVarBinOpPas` — the PASCAL entry
  point, which exists precisely because a shared runtime cannot see
  `PyProgramMode` — rewrites tkShr (119) to the out-of-band opcode **1119**,
  and `VarBitwiseInt` reads 1119 as "shift right, logically". NilPy enters
  `PXXVarBinOp` directly and never sees 1119. One emission, two policies, the
  language expressed by WHICH entry point ran.

## The second defect, found by not believing the first fix

After the change x86-64 and aarch64 answered 9223372036854775802 and i386 and
arm32 still answered **-6** — the arithmetic answer, apparently unfixed. It was
not. Four probe builds (return the opcode; return a sentinel from the arm;
print the operands; print the computed result) established that on i386 the
opcode arriving was 1119, the arm WAS taken, and the value computed inside
`VarBitwiseInt` WAS 9223372036854775802. The wrong number appeared only at the
`writeln`.

`PXXWriteVariant`'s integer arm read the payload as `PWord`, which
`builtinheap.pas` defines as `^NativeInt` — a MACHINE word, four bytes on i386
and arm32. `9223372036854775802` is `$7FFFFFFFFFFFFFFA`; its low dword is
`$FFFFFFFA`, which prints as -6. The arithmetic answer and the truncated
logical answer are the same number, which is why the bug looked like the bug it
was hiding behind. Changed to `PInt64` — the payload of BOTH integer tags is
documented in `defs.inc` as a full Int64 — and the other three `PWord` reads in
that routine (a tag, a Boolean's 0/1, a string HANDLE) are correct as they are.

That one-line read fixed far more than this ticket: `v := 1; v := v shl 40`
wrote 0 on i386 and arm32 and now writes 1099511627776; `v(3000000000) * 2`
wrote 1705032704 and now writes 6000000000. Every integer Variant wider than
32 bits rendered wrong on those two targets, silently, for as long as the
runtime renderer has existed.

## Verification

| row | x86-64 | i386 | arm32 | aarch64 |
| --- | --- | --- | --- | --- |
| `Variant(-12) shr 1` | 9223372036854775802 | same | same | same |
| `Int64(-12) shr 1` | 9223372036854775802 | same | same | same |
| `shl`/`and`/`or`/`xor` on -12 | agree with static | agree | agree | agree |
| `v(1) shl 40` rendered | 1099511627776 | 1099511627776 | 1099511627776 | 1099511627776 |
| `test_variant_bitwise_and_not` | ALL OK | ALL OK | ALL OK | ALL OK |
| `test_variant_writes_every_tag` | stream unchanged | unchanged | unchanged | unchanged |

NilPy is untouched: `-12 >> 1` is -6, `-1 >> 3` is -1, `1 << 40` is
1099511627776 and `2**70 >> 4` is 73786976294838206464, all matching CPython
3.x measured side by side.

`tools/gate.sh quick` GREEN; self-host converged after 1 round.

## What is deliberately NOT here

* **FPC's 32-bit narrowing.** `v(-12) shr 1` is 2147483642 there. That is the
  decision this ticket was re-filed from (decide-variant-bitwise-width, option
  2) and it stands: we care that a Variant answers what the same operator
  answers on a static operand of the same language, not that we reproduce a
  third reading.
* **riscv32.** It refuses `var_store` in IR codegen outright — it has no
  Variant support to fix.
* **Boxing an Int64 INTO a Variant on the 32-bit targets**, which still
  truncates: `a := l` with `l: Int64 = -12` yields a Variant holding
  4294967284. That is the i386/arm32 fat-slot model, a different mechanism from
  either half of this fix, and it is filed as
  [[bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32]].
  `test/test_variant_bitwise_and_not.pas` loads its agreement rows from a
  literal for that reason, with the workaround named in its header so it is
  deleted when that ticket lands.

## Files

* `compiler/ir_codegen.inc` — both `shr` emissions in `EmitVarBinOp`.
* `compiler/builtin/builtin.pas` — `PXXVarBinOpPas` substitutes opcode 1119.
* `compiler/builtin/builtinheap.pas` — `VarOpIsBitwise` and `VarBitwiseInt`
  accept 1119; `PXXWriteVariant` reads the integer payload as `PInt64`.
* `test/test_variant_bitwise_and_not.pas` — the "not covered" note replaced by
  six variant-equals-static rows and a wider-than-32-bit row.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
