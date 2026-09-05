
## 2026-09-06 (frankS) — TWO defects found, one mechanism still open; probe added

Reproduced on native x86-64 at `64f260c3618d`. Added `PXXDBG=a.slslot`, which
prints the slot layout from **both ends of the one rule that has two spellings**
— what `AssignStacklessSlots` decided, and what the for-in desugar actually
stores to.

### Defect 1 — the caller addresses slots by ARGUMENT INDEX, the generator by SLOT INDEX

`ParseForInGeneratorAST` (`pasparser_stmt.inc:~515`) stores argument `k` at
`SL_OFF_SLOTS + 8*(k-1)`, and its own comment states the assumption:
`SlSet(__g, SLOTS+8k, ak) for each provided arg`. The generator's save and
restore (`SLSaveLocals` / `SLRestoreLocals`) use `SL_OFF_SLOTS + 8*SymGenSlot[i]`.

**Those agree only while every parameter is one word.** A Variant takes two, so
any parameter AFTER a Variant is addressed by the caller one slot low:

```
Gen(a: Variant; b: Integer)   a -> slots 0,1 (48,56)   b -> slot 2 (64)
caller writes                 a0 -> 48 (ok)            a1 -> 56  = a's HIGH WORD
```

`b` is never written and reads 0; `a` is corrupted in its second word. That is
`w_vi` / `probe3`, and it is the **no output at all** column of the table above.

This is the missing-copy shape again: one rule, two spellings, and the two
disagree only in a case nothing in the tree exercised.

### Defect 2 — a Variant parameter is stored as ONE machine word

`GenSlSetStmt2` emits `SlSet(g, off, val)`, and `SlSet(g: Pointer; off, val:
Int64)` writes exactly 8 bytes. A Variant is a 16-byte {tag, payload} pair, so
half of it is never written; `SlNew` zeroes the instance, so the other half stays
0. The code comment above `PyGenArgNeedsCell` states the assumption outright —
*"stored into its persistent instance slot by the for-in desugar, as ONE machine
word"* — and handles the NilPy variant case with a heap cell while the **Pascal
by-value Variant case has no arm at all**.

`SLSaveLocals`/`SLRestoreLocals` already do this correctly with
`SlBlob`/`SlUnblob` and an explicit 16. Only the caller does not.

### What is measured, and what is NOT

Measured and solid:

- Native reproduction; **only Variant**. A `record` parameter and an
  `AnsiString` parameter both leave the other parameters intact (`prec`, `pstr`
  print `11 22`), so this is not "any multi-word parameter".
- The generator's own restore is **correct** — `PXXDBG=a.ir:Gen` shows `a` read
  from 48 and `b` from 56, identically in the working and broken programs.
- For the case where the Variant is LAST, `PXXDBG=a.slslot` shows
  `storeoff == realoff` for every argument, so Defect 1 is **not** what breaks
  that case.
- `SlSet(g, 64, v)` with a Variant `v` works standalone — writes 33, leaves
  slots 0 and 1 intact. **Negative result: this is not a simple ABI mismatch**,
  and nobody should re-derive that theory.
- The failure is value-independent (`c` = 0, 1 or 33 all corrupt identically),
  so it is structural at compile time rather than a malformed-tag runtime effect.

**NOT explained, and this is the open question.** With the Variant LAST
(`Gen(a: Integer; b: Integer; c: Variant)`), the offsets are right and the
restore is right, yet `a` and `b` both read **0** — so the caller's stores to 48
and 56 are not taking effect when a Variant argument is present anywhere in the
list. Defect 2 alone should corrupt only `c`. Something about building the
argument sequence with a Variant in it is losing the earlier stores, and I did
not find it. The next reader should start there and not at the offsets, which
are proven correct in that case.

### Where to look next

`ParseForInGeneratorAST`'s `assignG` chain, the `argHoist` splice in particular.
Note the Variant-variable form (`pv`) fails identically to the literal form, so a
conversion temp is **not** the trigger.

Fixing Defect 2 needs a `SlBlob` of the argument's address with `TypeSlotSize`
bytes at `SL_OFF_SLOTS + 8*SymGenSlot[param]`, which fixes Defect 1 in the same
edit — the two share one repair. Do not fix Defect 1 alone: it would move the
Variant to the right offset and still write half of it.

### Not verified

Still only x86-64 native and wasm32. The ticket's own note that 32-bit targets
are the interesting ones stands, and Defect 1 makes that sharper — `8*(k-1)`
is a hardcoded 8 on every target, while `TypeSlotSize` is not.
