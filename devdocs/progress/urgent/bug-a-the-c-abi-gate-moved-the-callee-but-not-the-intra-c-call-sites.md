---
track: A
prio: 65
type: bug
status: new
blocked-by: []
owner: ""
summary: "b4ff9adea routed the prologue and epilogue through CProcUsesCAbi but left the seven call-site guards on `not CProgramMode`, which is False inside a C unit. So in a Pascal-used C unit the callee moved to the C ABI and intra-unit C->C call sites did not: an intra-C call passing a double returns 0 instead of 1000 on aarch64 and i386. Regression, found by the verification row neither wired subject can reach."
---

# The C-ABI gate moved the callee but not the intra-C call sites

Regression in `b4ff9adea`. Found during the paired verification of that commit —
by the one subject the two wired ones **structurally cannot reach**.

## Measured, paired, both sides built from source

Baseline `b4ff9adea^` = `24c1e746bf69`, experiment `d4f1a4a0b3d9`. Subject:
`unit_x.pas` whose implementation is a C TU, where a C function calls **another
C function in the same unit** passing a `double`, and Pascal calls only the
int-taking outer one.

| subject | x86-64 | aarch64 | arm32 | riscv32 | i386 |
| --- | --- | --- | --- | --- | --- |
| Pascal→C bridge (the ticket's red) | PASS | FAIL→**PASS** | FAIL→**PASS** | PASS | FAIL→**PASS** |
| pure C control | PASS | PASS | PASS | PASS | PASS |
| **intra-C call in a Pascal-used unit** | 1000 | **1000→0** | 1000 | 1000 | **1000→0** |

The two wired subjects are green and the commit's own goal is met. This third
population is new.

## It is the ARGUMENT side, not the return

The obvious reading — the new `CdeclResultInFpReg` epilogue arms, which landed
on exactly these two targets — is **wrong**, and splitting the shape kills it:

| variant | aarch64 | i386 |
| --- | --- | --- |
| A `double` arg, **int** return | **0** | **0** |
| B `double` arg, `double` return | **0** | **0** |

A has no float return at all and fails identically. Argument marshalling.

## Mechanism

`b4ff9adea` routes the prologue (`cparser.inc`) and the epilogue
(`symtab.inc`) through the new `CProcUsesCAbi`. Its diff touches only
`cparser.inc`, `defs.inc`, `symtab.inc` — so the **seven call-site guards are
unchanged** and still read `ProcCdecl[procIdx] and (not CProgramMode)`:
`ir_codegen_aarch64.inc:2993,3188`, `ir_codegen_arm32.inc:2658,2965`,
`ir_codegen386.inc:3204,3561,3646`.

Inside a Pascal-used C unit `CProgramMode` is **True**
([[bug-c-a-c-function-s-calling-convention-depends-on-the-target]] — `ParseCUnit`
sets it exactly as `ParseCProgram` does), so those guards are False, the caller
marshals positionally, and the callee's prologue has moved to the C ABI.
**Positional caller, C-ABI callee** — the ticket's original disagreement,
relocated from the Pascal↔C boundary to the C↔C one inside a gated unit.

## Fix

Route the seven guards through `CProcUsesCAbi(procIdx)` as well. That predicate
exists precisely so this question has one answer
([[decide-does-a-c-function-always-use-the-c-abi-or-only-when-a-pascal-program-uses-it]]
names the destination above it); the third site simply was not routed through
it. **Requirement 3 of the parent ticket is not met until all three are** — the
predicate is a single place only if everything asks it.

## arm32 and riscv32 are NOT evidence of correctness

arm32 is soft-float, so positional word-based and AAPCS32 coincide for
`(double, int)`; riscv32's prologue is not gated at all. Only one shape has been
tested. The parent ticket needed `three_ints` to expose i386 and `int_first` to
expose arm32 — three targets, three mechanisms, no single shape finding all
three — and the same caution applies here. **Vary the shape on all four cross
targets before calling arm32 and riscv32 clean.**

## Reproduce

`/tmp/claude-1000/.../scratchpad/cprog/` — `px.pas` (the 1000-row) and `py.pas`
(the A/B split). Both are three small files: a C TU, a Pascal unit whose
implementation it is, and a program. **They belong in `test/`** as a third wired
subject beside `test_c_abi_pascal_caller.pas` and `c_abi_pure_c_control.c`;
frankC is adding that, since a population that no wired test reaches is how this
got through two independent verifications.
