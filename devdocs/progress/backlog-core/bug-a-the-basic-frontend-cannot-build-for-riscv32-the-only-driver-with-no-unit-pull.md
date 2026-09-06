---
track: A
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-07
found-by: frankA
tags: [basic, riscv32, cross-target, softfloat]
blocked-by: []
summary: "`test_basic_comprehensive.bas --target=riscv32` fails with `this target has no FPU and the soft-float kernel __pxx_l2d is not linked`. BASIC is the only skeleton driver with NO target refusal at all -- it has crossed to i386, aarch64 and arm32 for some time with nothing measuring it -- and the last one still missing the target-runtime unit pull. THE OBVIOUS FIX WAS TRIED AND REVERTED, which is why this is a ticket: adding PullTargetRuntimeUnits before PatchProgramEntryJump (the placement that fixed the other five drivers) made BASIC fail on aarch64 and arm32 with `invalid IR symbol reference in load_sym` -- it BROKE two targets that worked to fix one that did not. bparser has its own unit mechanism (BSourceUsesAUnit, passed to EmitProgramPrologue) and the two interact; nobody has established how. Reverted rather than shipped, and BASIC is back to exactly its previous three-target state."
---

# BASIC cannot build for riscv32, and the obvious fix breaks two targets

## Measured 2026-09-07, compiler sha256 `16389396da97`

    pascal26:5396: error: this target has no FPU and the soft-float kernel
    __pxx_l2d is not linked; add `uses softfloat` to the program

i386, aarch64 and arm32 are all **identical to the native run**. Only riscv32
fails, and it fails with this ticket's sibling defect
(`bug-a-a-frontend-cannot-see-that-a-backend-calls-library-routines-it-never-mentions`).

## Two findings, and the second is why this is not a two-line fix

**BASIC has been crossing to three targets and nothing measures it.** It is the
one skeleton driver with no refusal, so nothing had to be lifted to read this —
the capability was already there and unrecorded, which is how a capability gets
lost. It is in `test-skeleton-frontends-cross-target` now, for those three.

**The fix that worked for the other five made BASIC worse.** Placing
`PullTargetRuntimeUnits` before `PatchProgramEntryJump` — the placement measured
correct for Ada, Fortran, Algol, LOLCODE and Whitespace — produced
`invalid IR symbol reference in load_sym` on **aarch64 and arm32**, which had
been green. A net loss of two targets for a gain of none, so it was reverted and
BASIC is back to exactly its previous state.

`bparser` differs from its five siblings in one visible way: it has its own unit
mechanism, `EmitProgramPrologue(False, BSourceUsesAUnit, True, jmpPatch)`, where
the others pass a constant `False`. The two mechanisms plausibly interact.
**Plausibly is the honest word — nobody has established it**, and the failing
symbol was not identified.

## Acceptance

riscv32 joins BASIC's row in `test-skeleton-frontends-cross-target` **and i386,
aarch64 and arm32 stay green in the same run**. That second half is the whole
requirement: the reverted attempt would have passed a riscv32-only check.
