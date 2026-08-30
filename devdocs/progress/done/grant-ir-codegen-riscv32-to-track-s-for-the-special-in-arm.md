---
slug: grant-ir-codegen-riscv32-to-track-s-for-the-special-in-arm
track: A
prio: 55
type: grant
status: done
found: 2026-08-30
---

# GRANT: `ir_codegen_riscv32.inc` → frankS (Track S), scoped to the `SPECIAL_IN` arm

**Granted 2026-08-30.** `ir_codegen_riscv32.inc` is Track A's file and frankS correctly
declined to take it on its own read, offering instead to file an A ticket citing the arm32
model. **Granting rather than splitting, and the reason is the finding itself.**

## Why the grant, not the split

`SPECIAL_IN` is missing from **both** 32-bit backends — riscv32 and xtensa — and confirmed
failing on the same two programs on each. The ticket that produced it exists because
**one arm of a double case was fixed and the sibling was not grepped for.**

> **Landing the repair on one backend and filing the other is that same defect, one level
> up.** It leaves riscv32 as "the next lane's surprise" — the exact phrase, and the exact
> outcome, `normalise-dont-special-case.md` exists to prevent.

A fix for a double-case bug must not itself be applied to one arm. So the two 32-bit
backends land the rule together, in one change, by the lane that has the model in context.

## Scope

- **`compiler/ir_codegen_riscv32.inc`** — the `SPECIAL_IN` arm only. Nothing else in the file.
- Port model is **arm32 / i386** (the two 32-bit arms that already carry it): walk the arg
  list, `IR_BLOCK` item = `lo..hi` range, plain item = equality, accumulate into a scratch
  register. No conditional execution on either target, so the `moveq` becomes a branch.
- Gate = the two named programs green on **both** backends, `make compiler/pascal26`
  (which is the fixedpoint), plus the xtensa/riscv32 differential rows.

## Collision check at grant time

frankA holds A/P and is in the `pasparser_*` files on the typed-const generic repair.
frank-optimize-b4 has **released** `ir_codegen.inc` and is on an x86-64 emitter ticket.
**Nobody is in `ir_codegen_riscv32.inc`.** `ir_codegen_xtensa.inc` is already frankS's.

## Note for whoever reads this next

riscv32's diagnostic for the missing arm is the generic *"standard builtin calls not
supported in bare-metal stage 1"* bucket — **face 144 still live on that backend**, and the
reason the gap was invisible there. Fixing the arm does not fix the message; that is
`bug-a-iropname-has-no-entry-for-seven-ir-ops` territory and stays A's.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
