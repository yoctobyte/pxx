---
track: A
prio: 65
type: bug
status: done
blocked-by: []
owner: frankA
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

---

## RESOLVED — seven guards, one predicate, and arm32 was red too

Fixed by routing **all seven** call-site guards through `CProcUsesCAbi(procIdx)`
and widening the predicate to name both populations:

```pascal
Result := (procIdx >= 0) and ProcCdecl[procIdx] and
          ((not CProgramMode) or CUnitOfPascalProgram);
```

`not CProgramMode` alone is the **Pascal caller** of a cdecl proc, which is what
the seven guards were written for and is correct as far as it goes.
`CUnitOfPascalProgram` alone is the **intra-C call inside a gated unit**. Both
reach the C ABI; a predicate naming either one is wrong at the other. Replacing
the guards with the narrow form would have broken the bridge subject exactly as
the wide-but-incomplete form broke this one.

Sites: `ir_codegen_aarch64.inc:2993,3188`, `ir_codegen386.inc:3204,3561,3646`,
`ir_codegen_arm32.inc:2658,2965`. The `3561` site is the variadic `vaFwd`
expression, which carried the same test in a third spelling.

### arm32 was NOT passing — the caution was right and the shape was too narrow

frankC flagged that arm32 and riscv32 passing might be a coincidence of the one
shape tested, and said to vary it before calling them clean. It is, and here is
the row:

| shape | aarch64 | arm32 | i386 | riscv32 | x86-64 |
| --- | --- | --- | --- | --- | --- |
| `(double, int)` | red | *green* | red | green | green |
| **`(int, double)`** | red | **RED** | red | green | green |
| `(int,int,int)` | green | green | **red** (321) | green | green |
| `(double,double)` | red | green | red | green | green |
| `(float, int)` | red | green | red | green | green |
| `(double,int)->int` | red | green | red | green | green |

arm32 needs `(int, double)` specifically — AAPCS32 puts a 64-bit argument in an
**even** core-register pair, and the word-based positional convention uses
`(r1,r2)`. That is the same discriminator `int_first` provides in the parent
ticket's bridge subject, and it is the only one of six shapes that finds arm32.
riscv32 is genuinely unaffected: its prologue is not gated.

### Measured, with the sha of every binary

- **Baseline `992065f21f33`** (pin v398, `91815a50e`): intra-C **FAIL on
  aarch64, arm32, i386**; PASS on riscv32 and x86-64. Bridge and control both
  PASS on all five — the two wired subjects cannot see this.
- **After `76d38e0bd420`**: intra-C **PASS on all five**; bridge and control
  still PASS on all five. `gate.sh quick` GREEN, fixedpoint 1 round.

### One row still red, and it pre-dates this

A seventh shape, `(double,int,double,int,double,int)`, does not **compile** on
arm32:

```
target arm32: ... argument block exceeds 4 core registers
```

That is [[bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area]] (open, p45), not
this fix. Confirmed rather than assumed: the **pinned** binary `992065f21f33`
refuses the identical source with the identical message.

### Why the harness could not have caught it

frankC owns this and said so first: the bridge subject has a Pascal caller and
the control is a pure C program where the gate is off, so **the population that
broke is the one neither wired subject can reach**. It found it by reading the
diff and noticing the guards were untouched — not by running the instrument.
The subject is worth wiring for that reason alone, and frankC is adding it.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
