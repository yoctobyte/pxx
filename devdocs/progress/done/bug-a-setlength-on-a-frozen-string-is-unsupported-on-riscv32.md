---
prio: 40
track: A
type: bug
status: done
summary: "SetLength(s, n) on a `string[N]` is a hard compile error on riscv32 -- `standard builtin calls not supported in bare-metal stage 1 (builtin id 101)`. Pre-existing, unrelated to the byte prefix, and it compiles on x86-64/aarch64/arm32. Pos and Copy on the same type DO compile on riscv32, so this is one missing builtin rather than a general gap. It cost the frozen-string reader matrix its two SetLength rows, which would otherwise cover a reader that appears in no census."
owner: frankB
---

# SetLength on a frozen string is unsupported on riscv32

```pascal
type TS10 = string[10];
var s: TS10;
begin
  s := 'hello';
  SetLength(s, 3);   { pascal26: error: target riscv32: standard builtin calls
                       not supported in bare-metal stage 1 (builtin id 101) }
end.
```

Measured 2026-09-02, default mode, no `-dPXX_SHORTSTRING`. **`Pos` and `Copy` on
the same type both compile on riscv32**, checked one at a time, so this is a
single missing builtin and not a blanket bare-metal restriction.

## Why it is worth more than its size

`SetLength` **reads** the length prefix before it writes one, and every
call-site census phase 2 ran counted `PXXWriteFrozenW` — writers. Comparison,
`Copy`, `Pos` and `SetLength` appear in none of them, and the byte-prefix
defects have all been in readers. So `SetLength` belongs in
`test_shortstring_through_a_pointer.pas`'s reader matrix and had to be removed
from it, because a hard compile error on one target costs the whole file there.

Restore those two rows when this lands — the file says so at the point they
were removed.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]

## Resolution (2026-09-03, frankB)

**Filed riscv32-only; xtensa had the identical gap and was measured, not
assumed.** Taking the ticket's claim as the scope would have left half of it:

| target | before |
| --- | --- |
| riscv32 | `target riscv32: standard builtin calls not supported in bare-metal stage 1 (builtin id 101)` |
| xtensa | `target xtensa: this builtin has no arm in the xtensa backend (builtin -101)` |
| x86-64, i386, arm32, aarch64, wasm32 | compiled |

Two different error strings for one absence — neither names SetLength, and the
riscv32 one names a *stage-1 bare-metal* restriction that does not exist (`Pos`
and `Copy`, also builtins, compile there). Both backends simply had no
`procIdx = -101` arm and fell through to the generic refusal at the bottom of
their call dispatch. `-102` (dynamic array / managed AnsiString) was already
present in both, which is why the gap read as target policy rather than as one
missing arm.

**The fix** is a `-101` arm in each, mirroring the x86-64/aarch64/arm32 ones:
evaluate the buffer address, push it, evaluate the new length, pop, and hand
both to `EmitStoreStrLenRISCV32` / `EmitStoreStrLenXtensa`, which own the
prefix-width choice — so the arms are correct under both modes without either
one naming a width. The xtensa arm uses `XtensaSlotOff`/`XtensaDropSlots`
rather than a hand-written stack offset, because the windowed and Call0 ABIs
index the expression stack in OPPOSITE directions and a literal offset is
silently wrong on exactly one of them; both ABIs were run.

**Verified** with a five-shape probe (local, global, by-value param, by-ref
param, SetLength-to-0): all seven targets × both modes produce identical output,
and xtensa matches under both ABIs. **Positive control:** with the two arms
reverted and the compiler rebuilt (`converged after 1 round(s)`), both refusals
return at the SetLength line — riscv32 with the exact string in this ticket's
summary.

**The two rows are restored, and the restoration is smaller than the ticket
expected.** `test/test_shortstring_through_a_pointer.pas` gets five SetLength
rows on the DIRECT spelling only (33 assertions, byte-identical to FPC 3.2.2).
The deref and field spellings stay out for a *different* reason, measured while
widening the probe and reproduced at the pin:
`SetLength(p^, n)`, `SetLength(r.f, n)` and `SetLength(arr[0], n)` are refused
on **every** target including x86-64 with `SetLength expects a string variable
in IR codegen`, because every backend's arm requires an `IR_LEA` of a symbol.
Filed as
[[bug-a-setlength-is-refused-for-any-frozen-string-that-is-not-a-plain-symbol]];
it is pre-existing and not a width bug.

**Wiring, while the file was open:** its "DEFAULT MODE ONLY" note was stale —
the flag rows it was waiting on are green everywhere now — so the three cross
rows gained a `-dPXX_SHORTSTRING` twin, x86-64 is wired natively in both modes
(the `Write(p^)` garbage that kept it out is closed), and xtensa is wired under
the flag. Xtensa in DEFAULT mode bus-errors on qemu before printing line one;
that reproduces on this file at HEAD without the SetLength rows, so it is
pre-existing and unrelated, and the flag row is not held hostage to it.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
