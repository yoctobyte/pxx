---
slug: bug-a-64-bit-multiply-overflow-is-unchecked-under-q-plus-on-riscv32-and-xtensa
track: A
prio: 25
type: bug
blocked-by: []
status: done
found: 2026-09-01
found-by: frankA
owner: unassigned
summary: "FIXED: {$Q+} did not catch a 64-bit*64-bit product overflowing Int64/QWord on ANY 32-bit target (i386, arm32, riscv32, xtensa printed the wrapped value, rc=0; x86-64 raised 215). Cause: such a product has no narrowing store for the existing check to sit at, and the 32-bit backends have no flag-setting 64-bit multiply. Fix: on TARGET_PTR_SIZE=4 a Q-tagged Int64/QWord multiply (unless both operands are <=32-bit ordinals) lowers to PXXMulOvfS64/U64 in builtinheap, which traps via a division check. {$Q-} is untouched: still a plain binop, no call, wraps with rc=0 (asserted)."
---

# 64-bit multiply overflow is unchecked under `{$Q+}` on riscv32 and xtensa

## The fact

```pascal
{$Q+}
var x, y, z: Int64;
begin x := 4000000000000000000; y := 4; z := x * y; WriteLn(z); end.
```

| target | result |
| --- | --- |
| x86-64 | `Runtime error 215 (arithmetic overflow)` |
| riscv32 | `1553255926290448384` — wrapped, no trap |
| xtensa | `1553255926290448384` — wrapped, no trap |

Note both wrong answers are **the same** wrong answer, which is the tell that
this is one shared mechanism and not two coincidences.

## Why it is separate from the narrowing-store check

32-bit overflow under `{$Q+}` IS caught on both, because Pascal widens the
arithmetic to Int64 and the wrap is caught at the narrowing store
([[bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently]]).
This case has **no narrowing** — destination and value are both Int64 — so the
store-side check cannot see it by construction. It has to be detected where the
64-bit product is formed.

## Where it would go

`EmitBinop64RISCV32` already takes `qchk`/`qchkUns` and handles checked add and
subtract of pairs; `tkStar` is the arm it does not check, and its own comment
records the deferral (*"unsigned checked mul stays deferred, like the 64-bit
pair path records"*). `EmitBinop64Xtensa` takes no `qchk` parameter at all and
would need one.

A 64×64 checked multiply needs the full 128-bit product, or an equivalent
pre-check on the operand magnitudes. On xtensa that is harder again: `muluh` is
UNSIGNED, so the signed high word must be reconstructed as
`hi_s = hi_u - ((l sar 31) and r) - ((r sar 31) and l)` — and under
`--xtensa-soft-mulhigh` there is no `muluh` instruction at all, so it becomes a
helper call inside an arithmetic operation.

## Ranking

Low deliberately. It needs an Int64 product past 2^63 with `{$Q+}` on, on a
32-bit cross target. Real, silent, and worth recording — but the 32-bit shapes
that reach it are the ones already covered. **Do not raise the prio to make it
visible**; it is reachable and correctly ranked, and both backends should be
done in one pass when someone takes it.

## Resolution (2026-09-24, frankH)

Re-verified at HEAD first: the gap was wider than the title -- i386 and arm32 also wrapped
(`BAD -2446744073709551616`, rc=0), and unsigned QWord too.

Fix in `compiler/ir.inc` (AN_BINOP lowering) + `PXXMulOvfS64`/`PXXMulOvfU64` in
`compiler/builtin/builtinheap.pas`. Signed: `r := a*b`; trap if `b=-1` and `a=Low`, or `a=-1`
and `b=Low`, else if `b<>0` and `r div b <> a`. Unsigned: `b<>0` and `r div b <> a`.

Test `test/test_qplus_int64_mul_traps.pas` (Makefile, beside test_qplus_narrowing_store):
four trap shapes (signed +, signed -, -1*Low(Int64), unsigned 2^40*2^30) exit 215; a control of
fitting products including exactly Low(Int64) and the largest square; and a {$Q-} row that must
WRAP with rc=0. Measured on x86_64, i386, arm32, riscv32, xtensa (qemu, posix,
--xtensa-soft-mulhigh), compiler bb17d23beea5: all rows as specified. `PXXDBG=a.ir:M` on a
Q-/Q+ pair: {$Q-} is one plain binop and no extra call on all four 32-bit targets; {$Q+} adds
exactly one call. gate quick GREEN. Inert for `$(PXX_STABLE)` users until the next pin.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
