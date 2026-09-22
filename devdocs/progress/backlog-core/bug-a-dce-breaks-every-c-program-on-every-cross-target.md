---
slug: bug-a-dce-breaks-every-c-program-on-every-cross-target
title: "`--dce` on a C program miscompiles on every cross target -- a seven-line hello world segfaults"
track: A
prio: 75
type: bug
blocked-by: []
status: backlog
owner: ""
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
