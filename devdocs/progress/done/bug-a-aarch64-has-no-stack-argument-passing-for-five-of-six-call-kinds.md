---
track: A
prio: 55
type: bug
blocked-by: []
resolved: PENDING-COMMIT
summary: "FIXED for the four PXX-INTERNAL call kinds -- direct, constructor, indirect, virtual -- which now share one EmitCallArgRegsA64 and three Errors are deleted. NilPy builds and runs on aarch64: `print(1+1)` prints 2, and a class-heavy program matches CPython. THE TICKET'S PREMISE IS CORRECTED: it is TWO mechanisms, not one refused six times. The remaining three sites -- external, variadic external, cdecl indirect -- are the AAPCS64 C convention with INDEPENDENT int/fp register banks and a per-parameter classification, which the internal convention (every argument 8 bytes in an x-register, by position) does not have. Re-filed as bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds; nothing currently reaches it.
## Fixed for the internal family — 2026-08-31 by frankA

`EmitCallArgRegsA64(nArgs, nArgTotal, xtra1, xtra2)`: args 0..7 into x0..x7,
args 8.. into an AAPCS64 outgoing block, extras (an indirect callee in x16, a
hidden indirect-result pointer in x8) loaded from the temps pushed below arg0.
Returns the bytes to drop after the call, 0 on the <=8 path which pops. Four
call sites, one mechanism; the direct call was moved onto it too, so the arm
that already worked cannot drift from the three that now do.

| kind | before | after |
| --- | --- | --- |
| direct | worked | on the helper |
| constructor | `Error` | works |
| indirect | `Error` ← NilPy | works |
| virtual | `Error` | works |
| external | `Error` | still refuses |
| variadic external | `Error` | still refuses |
| cdecl indirect | `Error` | still refuses |

## The premise was half right, and the correction is the useful part

The ticket said *one mechanism, refused six times*. Measured, it is **two**:

- the **pxx internal convention** — every argument is 8 bytes in an x-register,
  assigned by position. Four call kinds, and they really were one rule spelt
  four times. That is what this fix deletes.
- the **AAPCS64 C convention** — integer/pointer args in x0..x7 and FP args in
  v0..v7, allocated from two INDEPENDENT banks with a per-parameter
  classification (and a by-ref float counting as a pointer, which the x86-64
  twin got wrong once already). Three call kinds. Sharing the internal helper
  there would be wrong, not merely incomplete.

Parking rather than microfixing the second half is deliberate
(`root-cause-over-microfix.md`): nothing reaches those three today, the rule is
different, and a C-interop marshalling bug is a segfault at a library boundary
rather than a wrong number.

## What caught the one real bug in it

`test/test_a64_stack_args.pas` — **one row per call kind**, because
`test_cross_many_params` exercises only the DIRECT call and is therefore exactly
the test that stayed green while five kinds refused. Every routine's answer
depends on arguments 8 and 9, the two that travel on the stack.

The ctor row printed `1508537076` for `10936` while the other three were already
right. **The constructor is the only kind that does something between
marshalling and the call** — it saved Self with `str x0, [sp,#-16]!`, which on
the stack-arg path moves sp 16 bytes BELOW the outgoing block, so the callee
read Self as argument 8. Self is arg0 and its temp is still live, so it reloads
from `[sp, #sz-16]` instead. A three-kind test would not have found it.

## Gate

- 28 aarch64 binaries (14 programs x -O0/-O3) **byte-identical** to a control
  built with the change reverted — the <=8-argument path, which is every
  program that compiled before.
- The new test fails on the pre-fix compiler with the indirect-call refusal.
- `make compiler/pascal26` converged; `tools/gate.sh quick` GREEN.
- NilPy: `print(1+1)` -> `2`; a class + list + for-loop program prints `25 6 ok`
  on aarch64, x86-64 and CPython alike.
