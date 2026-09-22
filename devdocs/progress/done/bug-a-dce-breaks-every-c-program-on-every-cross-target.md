---
slug: bug-a-dce-breaks-every-c-program-on-every-cross-target
title: "`--dce` on a C program miscompiles on every cross target -- a seven-line hello world segfaults"
track: A
prio: 75
type: bug
blocked-by: []
status: done
owner: frankb-8e
created: 2026-09-22
found-by: frankh-c0
summary: "`--dce` MISCOMPILES EVERY C PROGRAM ON EVERY CROSS TARGET, and a seven-line hello world is enough: `int add(int a,int b){return a+b;} int main(void){printf(\"%d\\n\", add(19,23));}` segfaults under qemu on aarch64 and arm32, and on riscv32 prints NOTHING and exits 0 -- the loud arm and the silent arm of one defect. `--no-dce` prints 42 on all three. PASCAL IS UNAFFECTED on the same three targets with the same flag, so this is the C FRONTEND crossed with a non-host backend and not DCE in general. PRE-EXISTING AND SHIPPING: reproduced with the pre-promotion compiler asking for `--dce` EXPLICITLY, so no default is implicated and `-O3` carries it today. WHY NOTHING SAW IT, AND IT IS A POPULATION HOLE RATHER THAN AN OVERSIGHT: the argument that licensed DCE into the free tier is that `tools/optdiff.sh` sweeps ~900 programs at -O0/-O2/-O3 and therefore makes the opt tier a whole-corpus `--dce` differential. That corpus DOES include `test/*.c` -- but optdiff builds for the HOST ONLY, so the differential is x86-64-shaped and cannot contain this. `compiler.pas`'s own comment already states the general form (\"the x86-64 whole-corpus differential that -O3 buys says nothing about xtensa\") and the same sentence covers aarch64, arm32 and riscv32. Separately, `bug-a-dce-refuses-every-target-except-x86-64` recorded arm32/aarch64 as VERIFIED BY RUNNING with five fixtures per target; those fixtures are Pascal, which is exactly the arm that still works, so that verification is sound about what it measured and silent about this. WHAT IT COSTS: it is the wall behind the `-O2` promotion measured at -66% over nine real programs -- promoting the pass and running a full tier gives 101 hard FAILs on plexus, concentrated in cross-target C (33 test-core, 20 test-riscv32, 13 test-aarch64, 12 test-arm32, 18 c-conformance), and this is the cause of essentially all of them. ONE OF THE 101 IS NOT THIS and is paperwork: `c_dce_entry_root` asserts the `-O3` image is strictly smaller than the `-O2` one, which a promotion empties. REPRO IS THREE LINES AND NEEDS NO FIXTURE -- see the body."
---

# `--dce` on a C program miscompiles on every cross target

## Repro

```sh
printf '#include <stdio.h>\nint add(int a,int b){return a+b;}\nint main(void){printf("%%d\\n", add(19,23));return 0;}\n' > /tmp/tiny.c
./compiler/pascal26 --dce --target=aarch64 /tmp/tiny.c /tmp/t && tools/run_target.sh aarch64 /tmp/t
```

## The matrix, measured 2026-09-22 at `311ebde9e`, compiler `303897e87b55`

| subject | target | `--dce` | `--no-dce` |
| --- | --- | --- | --- |
| seven-line C | aarch64 | **SIGSEGV** | `42` |
| seven-line C | arm32 | **SIGSEGV** | `42` |
| seven-line C | riscv32 | **empty output, exit 0** | `42` |
| `test/caarch64_aggregate_byval.c` | aarch64 | **SIGSEGV** | correct |
| `test/caarch64_aggregate_byval.c` | arm32 | **SIGSEGV** | correct |
| `test/caarch64_aggregate_byval.c` | riscv32 | **empty output** | correct |
| C, **x86-64 native** | — | correct | correct |
| **Pascal** (`for i:=1 to 3 do WriteLn(i*7)`) | aarch64 / arm32 / riscv32 | **correct** | correct |

**The Pascal row is the control that scopes this.** Same pass, same three
backends, same flag, and it works — so "`--dce` is broken on cross targets" is
refuted by the same run that finds this. It is the C frontend crossed with a
non-host backend.

**The x86-64 C row is the control that explains the blindness.** Everything
that routinely exercises `--dce` runs there.

## Not caused by any default

Reproduced with the pre-promotion binary (`c24a11f2beb3`, DCE off at `-O2`)
asking for `--dce` explicitly: identical SIGSEGV on aarch64 and arm32. So this
is a **shipping path** — `-O3` turns the pass on and has since 2026-08-21 — and
not a consequence of anything proposed.

## SCOPE — what is NOT exposed, so this does not over-travel

**Bare-metal ESP work is not exposed.** The exposure is *C on a cross target*,
and the ESP bare fixtures (`test_esp_bare*.pas` and the rest of that family) are
**Pascal**, which the control row above shows is unaffected on all three
targets. What IS exposed is `lib/crtl` and anything C aimed at riscv32, arm32,
aarch64 or xtensa. Written down because "riscv32 + silent + `--dce`" reads like
an ESP emergency and is not one.

## riscv32 is the dangerous arm

aarch64 and arm32 crash, which is the cheap case: a location and a signal.
riscv32 **prints nothing and exits 0**. A harness asserting only the exit status
would call that a pass, and `tools/expect_same.sh` catches it solely because it
compares output. Two arms of one defect, and the quiet one is the one to keep in
mind when judging whether a fix is complete.

**THE REGRESSION TEST MUST ASSERT THE OUTPUT (`42`), NEVER THE EXIT STATUS** —
and this is a prediction about how the fix will go wrong, not a style note.
Whoever takes this will debug on a **crashing** target, because a SIGSEGV has a
location and the silent arm does not. So aarch64 and arm32 will look fixed
first, and **a fix verified there can leave riscv32 silently wrong while every
exit-status assertion passes.** Same class as the leak that printed
`OPENARRAYFRESH OK` with 1504 of 3000 arrays leaked: the assertion was
physically unable to observe the defect. Assert the bytes.

**AND THE TWO ARMS MAY NOT BE ONE CAUSE — SEPARATE THEM BEFORE CALLING EITHER
FIXED** (frankb-8e, 2026-09-22, taking the ticket). aarch64/arm32 crashing says
the entry path went somewhere invalid. riscv32 exiting 0 with no output is
consistent with that **and equally consistent with a BODY dropped whose absence
merely skips the `printf`** — two different defects that the matrix above
cannot tell apart, because both produce an empty stdout. The matrix is evidence
that something is wrong on three targets, not evidence that it is the same
something. **Say in the resolution which arm each assertion actually
exercises.**

## Where to look

The known C-rooting fix — `bug-a-dce-on-a-c-program-drops-main-because-nothing-
roots-the-c-entry-path`, closed — records that the C entry stub's call to `main`
is **hand-patched with an absolute address, never through `CallFix`**, so the
call graph has no edge to it. That fix roots the C entry path. The shape here
looks like the same seam on a backend whose entry stub or call patching differs
from x86-64's: something reachable only through a hand-patched address, dropped
or left unrelocated where the host arrangement happens to survive.

**Note the sibling that was just found in the same file**: `IramCallFix` was
marked and never compacted, which is one array touched in `DceMark` and nowhere
else (`8417dc950`). **Grep `dce.inc` for the other tables the C/cross entry
path uses before theorising** — this family's one omission has now recurred
five times.

## What it gates

The `-O2` promotion. PROMISE is measured at **-66%** over nine real
`examples/**` programs (4,424,828 -> 1,475,708 bytes) with the self-host
fixedpoint converging. PROOF is a full tier, which is **RED with 101 hard
FAILs** until this is fixed. Nothing else stands in the way:
`bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce` records the rest.


## 2026-09-22 (frankb-8e) — FIXED. One missing line, and a FOURTH broken target nobody listed

`PatchEntryStubCall` (`symtab.inc`) recorded an entry ROOT on all five targets
and recorded the call SITE on one. Those are two different questions:
`RecordEntryRoot` keeps the CALLEE alive, `RecordCodeRefAt` keeps the CALL
aimed at it. Only the second was missing, and only on the four cross arms.

### The measurement

aarch64, `int main(void){printf("%d\n", add(19,23));}`, `--dce`:

```
IN: 0x0040012c:  ... 9401d4d4        <- bl, imm26 = 0x1d4d4
    target = 0x400138 + 0x75350 = 0x475488
SIGSEGV si_addr=0x475488, si_code=1 (MAPERR), before ANY syscall
```

`0x475488` is inside the **pre-DCE** code segment (`0x400000-0x4c0000`) and
above the top of the shrunken one (`0x430000`). The stub branched where `main`
*used to be*. `main` was alive and correct the whole time —
`--dce-why` on the broken binary prints `main <- [entry stub call]`, so the
root that a previous fix installed was doing its job and was never the issue.

### THE FIX IS ONE RECORD, HOISTED

```pascal
  RecordEntryRoot(procIdx);
  if TargetArch = TARGET_XTENSA then
    RecordCodeRefFull(patchPos, bodyAddr, 1, anchorPc)
  else
    RecordCodeRefFull(patchPos, bodyAddr, 1, -1);
```

**Every encoding this routine writes already had a matching arm in
`PatchCodeRefSlot`** — arm32/aarch64 `BL` via `linkReg`, riscv32 via
`PatchRv32LinkSlot`, xtensa's literal delta via the anchor. Nothing new had to
be written to re-aim them; the pass simply was never told the sites existed.
`linkReg = 1` because every site here is a CALL. The x86-64 arm ignores it.

**It was present, in one branch, and that branch says why it is there:**
*"...and on the rel32 targets, the SITE moves too when a pass compacts the code
between here and the body. That is exactly what CodeRef records."* True of every
target, written inside the `else`. Hoisted rather than copied into four
branches — the same normalisation `EmitCallToCode`'s own header argues for.

### A FOURTH TARGET: XTENSA. Measured, not inferred

The report listed aarch64, arm32, riscv32. **xtensa was broken identically** and
is fixed by the same line. Established by stash-and-rebuild, not by reading:
without the fix, `qemu-xtensa` gives SIGSEGV; with it, `dce-c-cross 1729 1729 0`.
It takes the **literal-anchor** form rather than a branch immediate, so it is
the one arm the other three do not exercise.

### AND A SECOND CALL SITE, also measured

`PatchEntryStubCall` has two callers in `cparser.inc`: the call to `main`, and
the call to `__pxx_run_initializers`, emitted only when the source mentions
`environ` (`CNeedsEnvironInit` is a token scan). **Both were broken**; an
`environ`-using C program segfaulted on aarch64 without the fix and prints
correctly with it. One line fixed both because both go through the one routine.

### CORRECTION TO THE MATRIX: riscv32 does NOT exit 0

The report has `riscv32 -> no output, exit 0`. Measured here, riscv32 gives
**rc=139, SIGSEGV**, like the other two — the compiler's rc is 0 and the
program's is 139, which looks like the wrapper-versus-job confusion this repo
keeps meeting. **So there is no quiet arm and the arity claim is simpler than
feared: four targets, one cause, one symptom.**

That does not retire the warning it came with, and the test is built to it
anyway: **every leg asserts STDOUT, not the exit status.** A dropped body *can*
produce an empty stdout and a clean exit, and a row asserting rc alone would
call that a pass.

### The enumeration, including the negatives

Promised as a list rather than a diagnosis, because this family has now missed
six times by someone checking the tables they happened to think of.

| what references a proc body from outside it | recorded? |
| --- | --- |
| `CallFix` | yes |
| `CodeRef` | yes |
| `ProcAddrFix` | yes |
| `MethodFixups` | yes |
| `IramCallFix` | yes (`8417dc950`, frankh-c0) |
| `PatchProgramEntryJump` | yes, all targets, per its own comment |
| **`PatchEntryStubCall`** | **root yes / SITE x86-64 only — THIS BUG** |

Checked and **not** affected, stated so the denominator is visible:

- Every `Patch32`/`Patch24` in `emit.inc`, `exception_emit.inc`,
  `asmtext*.inc` writing a branch: all **intra-body or intra-stub**. A body
  moves as a unit and the stub region is contiguous, so a displacement wholly
  inside one of them is invariant under DCE. `ExcLongJmpAddr` and its branches
  are the largest such group and are all inside one stub.
- Every `Procs[].BodyAddr` consumer in `elfwriter.inc`: those run at **write
  time, after `DceRun`**, and read the final value. Correct by construction.

So the live set was two sites in one routine, and both are fixed.

### Verified

| target | `--no-dce` | `--dce` | image |
| --- | --- | --- | --- |
| x86_64 (control) | `42` | `42` | 336520 -> 78472 (-77%) |
| aarch64 | `42` | `42` | 799312 -> 209488 (-74%) |
| arm32 | `42` | `42` | 848504 -> 156280 (-82%) |
| riscv32 | `42` | `42` | 881248 -> 168544 (-81%) |
| xtensa | `42` | `42` | code 674387 -> 120963 |

The shrink column is half the claim: a "fix" that switched the pass off would
also print 42.

### The test, and it FAILS on the unfixed compiler

`test/test_dce_c_cross_entry.c` in the **quick** tier, four cross legs plus the
x86-64 control, each leg comparing `--dce` against **its own** `--no-dce` leg
rather than a fixed string — one field legitimately differs per target, since
`CNeedsEnvironInit` exits early on xtensa so `environ` is uninitialised there
and the third number is 0 rather than 1. Each leg asserts the oracle printed
`1729 1729` first, so it cannot pass on a broken reference, and asserts the
image shrank, so it cannot pass on a pass that dropped nothing.

**Mutation tested**: with the fix stashed and the compiler rebuilt, the job
goes FAIL; restored, GREEN. It pins the defect rather than merely running
beside the repair.

The fixture reaches **both** call sites (it mentions `environ`) and prints 1729
twice — not 0, not 1, not a length, not a pointer width.

## Log
- 2026-09-22 — resolved, commit a79934842.
