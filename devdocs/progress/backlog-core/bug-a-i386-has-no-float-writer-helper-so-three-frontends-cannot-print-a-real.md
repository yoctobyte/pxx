---
track: A
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-07
found-by: frankA
tags: [i386, float, cross-target, fortran, algol, basic]
blocked-by: []
summary: "`compiler error: float writer helper not found` on i386, for a program that writes a REAL. The Fortran and Algol skeletons hit it and are refused for i386 because of it, while COMPILING AND RUNNING CLEAN on aarch64, arm32 and riscv32 -- so this is not a 32-bit story and not a width story, it is i386 specifically. The message is internal-fault-shaped, which makes it a defect rather than a refusal: it names a compiler-internal helper, offers the user nothing to do, and appears at the end of a successful parse. Measured 2026-09-07 with the frontends' x86-64-only refusals temporarily lifted; both fixtures print reals. BASIC is the sibling reading -- it writes reals too, has never had a refusal, and works on i386 -- so whatever the working path is, it exists on i386 and these two do not reach it."
---

# i386 has no float writer helper

## Measured 2026-09-07, compiler sha256 `6cb3695cbedc`

    pascal26:33: error: compiler error: float writer helper not found

`test_fortran_skeleton.f90` and `test_algol_skeleton.alg`, `--target=i386`.
Both compile and run **identically to their native output** on aarch64, arm32
and riscv32.

| | x86-64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| Fortran skeleton | ok | **fail** | ok | ok | ok |
| Algol skeleton | ok | **fail** | ok | ok | ok |
| BASIC (writes reals, never refused) | ok | **ok** | ok | ok | — |

**The BASIC row is the one that makes this a defect rather than a gap.** BASIC
writes reals and works on i386, so a working i386 float-write path exists; these
two frontends do not reach it. Whatever selects it is not being satisfied here —
not measured which, and that is the first thing to find out rather than guess.

## Why the message matters as much as the failure

`compiler error: <helper> not found` is **internal-fault-shaped**: it names a
compiler-internal routine, gives the user nothing to act on, and arrives after a
parse that succeeded. Compare LOLCODE's riscv32 refusal, found in the same
sweep — *"target riscv32: frozen tyString concat unsupported; only
literal+literal folds (combine nested string literals)"* — which names the
construct and the workaround. That one is a limitation. This one is a bug.

## Status of the two frontends

Both are refused for i386 and accepted for x86-64/aarch64/arm32/riscv32, with
this ticket named at the refusal. **The refusal is narrow and dated on purpose:
it excludes ONE target for ONE measured reason**, which is what makes it
retireable — unlike the x86-64-only refusals it replaced, which excluded four
targets for a reason nobody had checked in months.

## Acceptance

Both skeletons produce output identical to their native run on i386, and the
i386 entry comes out of both refusal lists in the same commit. The row is
already written: `test-skeleton-frontends-cross-target` covers both fixtures and
currently reports them REFUSED for i386, by name — so the reading flips from
"refused on purpose" to a compared row without a new harness.
