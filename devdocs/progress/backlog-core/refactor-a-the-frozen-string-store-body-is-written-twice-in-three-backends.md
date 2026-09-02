---
track: A
prio: 30
type: refactor
status: open
created: 2026-09-02
found-by: frankA
owner: ""
summary: "i386, aarch64 and arm32 each hold the frozen `string[N]` store body TWICE — once in IR_STORE_SYM (`s := v`) and once in IR_STORE_MEM (`p^ := v`) — identical instruction for instruction, differing only in where the capacity comes from (SymStrCap[si] against Integer(IRIVal[node])). MEASURED, not asserted: after e4cba526a the tyChar arm now appears twice in each of the three files, six copies where there were three, so the duplication GREW as a side effect of fixing the bug it caused. That bug is exactly what duplication predicts: only the SYM copy had ever grown a tyChar arm, so `s := c` compiled and `p^ := c` did not, on precisely the three backends with no second copy of it (bug-a-char-into-shortstring-through-a-pointer-is-x86-64-only). THE EXTRACTION IS ALREADY WRITTEN AND WAS MEASURED: one EmitFrozenStrStoreBody<arch> per backend called by both arms, byte-identical across 32 corpus binaries on each of i386/aarch64/arm32 with ZERO changed. Net line change was measured at -12 / -8 / +7 (i386 / aarch64 / arm32) on the PRE-transplant tree, where that diff was extraction AND the char fix together; the deletion against today's tree is larger because a second copy now exists per file, and that number is NOT measured. It is NOT landed — the transplant won the race and the tree is in a stand-down window for the prio-100 shortstring relayout. THE TRANSPLANT'S OWN AUTHOR ARGUES FOR THIS: frankC, 2026-09-02, *\"the author of the transplant thinks the extraction supersedes it... I would rather the tree ended up right than that my version stayed in it\"*, having named normalise-dont-special-case in the transplant commit itself. The banked patch is REFERENCE ONLY and does NOT apply — it was cut against the pre-transplant tree; re-derive rather than git apply."
---

# The frozen-string store body is written twice in three backends

- **Type:** refactor (codegen) — Track A
- **Do NOT start this during the `feature-p-implement-the-real-tyshortstring-byte-prefix-layout`
  window.** That work re-types `string[N]` and will rewrite these arms; doing
  both at once means resolving an extraction against a relayout in hand-encoded
  backends, which is the worst version of this job. **Check first whether the
  relayout already collapsed them** — if it did, close this as done-by.

## The duplication, measured

Each of `ir_codegen386.inc`, `ir_codegen_aarch64.inc` and `ir_codegen_arm32.inc`
contains the same body twice: write `[len][chars]` into a frozen buffer, with
the destination already in the register the caller loaded and the source being a
char ordinal, a managed handle, or a frozen-string address. The only difference
between the copies is the capacity expression.

```
$ grep -c "char ordinal -> \[len=1\]\[char\]" compiler/ir_codegen{386,_aarch64,_arm32}.inc
2   2   2      # after e4cba526a; it was 1 1 1 before
```

**The duplication grew as a side effect of fixing the bug it caused**, which is
the cleanest possible statement of why this ticket exists. Nobody did anything
wrong: the transplant was the smallest correct change that unblocked Track T's
cross fuzz rung, and the ticket it closed said "same file, same registers,
transplant not port".

## Why it is worth doing rather than tolerating

`normalise-dont-special-case.md`'s claim is not aesthetic — it is that the
second path is the one that stays broken, and here that already happened once
and cost an evening across two sessions. Only the SYM copy ever grew a `tyChar`
arm; `s := c` compiled and `p^ := c` did not, on exactly the three backends
without a second copy of it. x86-64 and riscv32 had it in both paths and were
never affected.

**Sharing the body makes that unrepresentable rather than fixed.** There is no
second arm left to fall behind.

## The work is already done and measured

`devdocs/dev/parked-patches/frozen-string-store-body-extraction-REFERENCE-ONLY.patch`

One `EmitFrozenStrStoreBody<arch>(srcTk, strCap)` per backend, called by both
arms. Measured before the race was lost, at the then-tip:

| target | corpus binaries byte-identical | changed | newly building |
| --- | --- | --- | --- |
| i386 | 32 | **0** | 1 |
| aarch64 | 32 | **0** | 1 |
| arm32 | 32 | **0** | 1 |

over the 35 tree tests containing `string[`, plus `gate.sh quick` GREEN and the
self-host fixedpoint converged. Byte-identity is the right control for an
extraction: everything that already compiled must emit the same bytes.

**Do not read this as a size estimate.** Net lines were **-12 / -8 / +7**
(i386 / aarch64 / arm32) — arm32 is net POSITIVE. The patch predates the
transplant, so in it each backend held the char arm only once and the diff is
extraction *and* the char fix in one. Against today's tree, with a second full
copy per file, the extraction deletes more — **that number has not been
measured and nobody should quote one until the re-derivation produces it.**

**THE PATCH DOES NOT APPLY.** `git apply --check` returns 1 against four files —
it was cut against the pre-transplant tree and the arms have since changed under
it. It is a REFERENCE for the shape and the helper text, not something to apply.
Re-derive against the tree of the day; the arms will be more similar than they
were, because both now contain the char case.

## The safety net already exists

frankC added cross rows for `test_char_into_shortstring_via_pointer` on
i386/aarch64/arm32/riscv32, executing under qemu, and the native row carries a
comment saying in capitals that it cannot fail for that bug (x86-64 was never
broken). **Those cross rows are the guard for this refactor** — a regression in
an extracted body shows up as a real cross-target failure rather than as a
silent shape change. Run them, and pair them with the byte-identity control
above, which is the check that catches a change that is wrong but still passes.

## Position of the transplant's author

Recorded because it is the thing that would otherwise be lost in a message
queue, and because a refactor over someone else's recent commit reads very
differently with and without it — frankC, 2026-09-02:

> I wrote in that commit message that the duplication is
> normalise-dont-special-case and then transplanted anyway. That was a deliberate
> call and I still think it was right for THAT hour ... But "smallest correct
> change now" is not the same claim as "right shape" ... when that window
> reopens, land it over mine ... I would rather the tree ended up right than
> that my version stayed in it.
