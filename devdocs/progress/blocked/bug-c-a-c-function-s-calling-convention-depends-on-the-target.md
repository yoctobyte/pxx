---
track: A+C
prio: 65
type: bug
status: blocked
blocked-by: [bug-a-the-shared-cdecl-spill-arm-cannot-yet-do-the-job-it-would-be-given]
owner: frankC
summary: "On x86-64 a C function uses the C ABI (SysV); on aarch64 and arm32 it uses pxx's INTERNAL positional convention, because cparser.inc's per-target prologue spills disagree. So `is this proc reached by the C ABI?` has a different answer per target, nothing names that in one place, and the `and (not CProgramMode)` guards on the aarch64/arm32 call arms exist to compensate. Split out of refactor-a-collapse-the-c-frontend-sysv-prologue-copy, whose x86-64 half landed byte-identical; this half is an ABI CHANGE and needs a behavioural gate, not byte-identity."
---

# A C function's calling convention depends on which target it is built for

Split out of [[refactor-a-collapse-the-c-frontend-sysv-prologue-copy]] rather
than bundled into it. That ticket's x86-64 half was a **pure deletion** — the C
copy and the shared arm already agreed, and the collapse changed no emitted byte.
**This half cannot be**: it changes what convention a C function uses.

## The table

| target | cparser's prologue spill | so a C function is... |
| --- | --- | --- |
| x86-64 | collapsed onto `EmitParamSpillsForTarget` (SysV) | **C-ABI** |
| aarch64 | `cparser.inc:11193` — positional, *"mirrors the Pascal aarch64 spill"* | **internal** |
| arm32 | `cparser.inc:11143` — positional, word-based | **internal** |

Nothing states that in one place, so every call site that wants to know "is this
proc reached by the C ABI?" encodes the answer per target — and it is not the
same answer.

## What it has already cost

`bug-a-a-c-mode-function-took-the-cdecl-call-path-on-aarch64-and-arm32` — five
p70 NEW-REDs (four `test-c-conformance-aarch64` shards plus `test-lua-cross`).
`ProcExternal[p] or ProcCdecl[p]` is **correct on x86-64 and wrong on
aarch64/arm32**, purely because of the table. Three strikes on that one
predicate: `b362` (indirect, lua + sqlite), `eeb51710e` (aarch64 direct),
`6d2939f38` (arm32 direct).

The `and (not CProgramMode)` guards now on the aarch64 and arm32 call arms are
**compensating for this table**. They are correct, and they are a workaround:
they stop a C-mode callee being called by a convention its own prologue does not
implement.

## Why it is its own ticket, and what its gate must be

The parent's gate is byte-identity, and byte-identity is the wrong instrument
here — a correct fix **will** change emitted bytes on aarch64 and arm32, by
design. Bundling the two would have let each change's gate excuse the other:
the byte-identity result would be false and *expected* to be false, and the one
signal that says "you changed behaviour" would be pre-explained away. (Exactly
frankA's argument for landing its riscv32 convention fix separately from this
refactor, and it applies again one level down.)

So this ticket needs:

1. A **behavioural** gate — C conformance on aarch64/arm32 plus `test-lua-cross`,
   asserting the new convention, not the old bytes.
2. **Removal of the compensating `not CProgramMode` guards in the same change** —
   they describe something accidental; once the prologues agree they would be
   describing something real, which means they are no longer needed and leaving
   them in hides whether the fix worked.
3. A single place that answers "is this proc reached by the C ABI?", so strike
   four does not land on a fourth call site.

## Carry-in from frankA's riscv32 fix

Expect **at least one arm to be correct already**. frankA's fix was a *deleted
case, not an added one*: the conformant layout already existed as the variadic
tail reversal gated on `ProcVariadic`, because a `va_arg` walk reads forward from
overflow and so needed psABI order. The ordinary path was the wrong one. The win
is deleting the disagreeing cases, not synthesising another.

## Re-rated p55 -> p65 and re-laned C -> A+C (coordinator, 2026-08-30)

frankC measured the shape where **no compensating guard applies** — a Pascal unit
whose implementation is a C translation unit (`uses './abi.c'`), so a Pascal-mode
caller meets a bodied C callee and the two sides must already agree. Binary at
fixedpoint `a7a03ffb95e1`; probe and runner in `/tmp/frankC-share/abi-probe/`.

```
shape                       x86-64  aarch64  arm32  riscv32  i386
f(double x, int n)            ok     0.00     ok      ok     Nan
f(int n, double x)            ok      ok     0.00     ok     Nan
f(int,int,int) -> 123         ok      ok      ok      ok     321
f(double a, double b)         ok    27.50     ok      ok     Nan
f(int,double,int,double)      ok   1034.00 refused    ok     Nan
f(float f, int n)             ok     0.00     ok      ok     Nan
```

**This is a silent-wrong-answer bug, not a consistency refactor.** Ordinary Pascal
calling ordinary C returns wrong numbers on three of five targets. CLAUDE.md's
compat table: *"real Pascal source compiles but runs wrong → bug, own lane, own
prio"*. p55-as-a-follow-on-refactor understated it.

**Why 65 and not higher:** the affected shape is a Pascal unit implemented by a C
TU, which is not yet common in the tree, and the two targets that matter most for
the ESP campaign — riscv32 and x86-64 — are clean. **Why not lower:** wrong
values, no diagnostic, and `i386` shows it with **no float at all**.

- **i386 is a fourth affected target and the worst — 6/6 wrong**, and nobody had
  listed it. `cparser.inc:11085` has its own i386 arm; `ir_codegen386.inc` carries
  the same three guards. Its divergence is argument **order**, hence `321` for
  `123`.
- **riscv32 is clean on all six** — frankA's psABI convention fix, and this
  ticket's own "expect one arm to be correct already" landing as written.

## It is an A ticket with a C-side deletion, and that is why frankC stopped

The prologue is Track C's; the compensating guards are **seven sites across three
Track A backends** — `ir_codegen_aarch64.inc:2993,3188`,
`ir_codegen_arm32.inc:2658,2965`, `ir_codegen386.inc:3204,3561,3646` — and this
ticket's own gate requires them in the same commit.

**Deleting the `cparser.inc` arms alone is strictly worse than the status quo**: an
AAPCS prologue against still-positional C-mode call sites breaks every C-to-C call
on three targets in order to fix the bridge.

**The destination already exists.** `EmitParamSpillsForTarget` has proven
`ProcCdecl` arms for i386 / aarch64 / arm32 / x86-64, each mirrored from that
backend's external-call marshalling — a classification validated every time pxx
calls libc with a float. The aarch64 arm's own comment records that it was **not**
mirrored from `cparser.inc`, *"that one is POSITIONAL and says so."* So the C side
is the same three-arm deletion the x86-64 half already was.

## The gate the ticket names cannot prove this

A pure C program is self-consistent **both before and after** — positional on both
sides today, AAPCS on both sides after — so `test-c-conformance-*` and
`test-lua-cross` can detect a **regression** here but can never go red-to-green.
**The differentiating shape is the probe above, and it belongs in `test/` as the
behavioural gate.** Anyone who runs the cross suites, sees green, and concludes
the convention was asserted has measured the wrong thing.

## Two notes recorded so they are not re-chased

- **No cross-gcc on this box** (no `aarch64-linux-gnu-gcc`, no clang, x86-64 gcc
  only), so "prototype against real gcc" is not executable for the two targets in
  question. **It also was not needed**: unlike the bitfield case, where only gcc
  could say what `sizeof` should be, a calling convention's observable is a
  returned number and that number is target-independent arithmetic. `f(2.5, 4)` is
  `10.00` everywhere, so a disagreeing target is wrong **by construction**, with no
  oracle to consult. gcc pinned the x86-64 row only.
- **A non-finding:** an early run segfaulted on `mix4` on x86-64 *and* riscv32 —
  the two clean targets. Pascal `Mix4` and C `mix4` differ only in case, bind
  case-insensitively, and recurse until the stack dies. Renaming gives `1234.00`.
  Not a crash on the correct path.

## DISPROVEN before dispatch: the seven guards are NOT the mechanism (frankA, 2026-08-30)

**Read this before the section above.** The re-lane and the p65 stand; the
*mechanism* the section above points at does not. frankA deleted **all seven**
`not CProgramMode` guards, rebuilt to a fixedpoint (converged 1 round,
`b9ead8dda12b` — a genuinely different binary), and reran frankC's probe:
**byte-for-byte identical failures.** Then restored and rebuilt back to
`faf762981c3c`.

They are **inert on this path**. `CProgramMode` is False when the program is
Pascal, so `ProcCdecl and (not CProgramMode)` already reduces to `ProcCdecl` in
exactly the configuration the probe exercises. Deleting them changes nothing
because they were never being consulted differently.

**Why it looked certain, and why that is the lesson worth keeping:** the three
backends carrying the guard are *precisely* the three failing targets, and the
three without it are x86-64, riscv32 and xtensa — of which riscv32 and x86-64 are
both clean. Five targets, two groups, **perfect separation, and completely
spurious.** No amount of reading would have separated the guard from the backend
it lives in, because the guard and the failure are both properties of *which
backend this is*. frankA's own note: *"I would have reported it as the mechanism
if deleting it had not been cheaper than reasoning about it."* That is
`devdocs/dev/debugging-playbook.md`'s rule — measure, do not reason — catching a
wrong root cause **one step before it was written into a dispatch**.

### What is actually established

- **IR is correct on both sides on i386** — args in order, no reordering — so the
  divergence is purely **codegen**: caller push order versus callee spill order.
- **`ProcCdecl` is not missing**: it *is* set True for a genuinely-new C proc at
  `cparser.inc:10736`, gated on `wasNewProc`.
- That narrows it to **which side consults `ProcCdecl` on the
  Pascal-caller-to-C-callee path**. Whoever takes this starts from the two codegen
  sides, **not** from the guards.

### Two rows that are not this ticket

- **It is not a regression of the cdecl campaign.** Against the *same* binary that
  fails the probe 6/6 on i386, `test_cdecl_bodied_narrow` passes **12/12** —
  including the three-distinct-integer order case, the exact shape the `three_ints`
  row fails — and `test_cdecl_bodied_wide` passes 3/3. Two different paths: the
  campaign covers Pascal-declared `cdecl` procs, this ticket a C-*defined* proc
  reached from a Pascal caller. Same symptom, different site.
- **The arm32 `refused` row is a separate, already-filed defect**:
  [[bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area]], which already carries
  frankA's warning about lifting the refusal. Do not fold it in here.

## RE-REVERSED: both halves or neither — measured paired (frankC, 2026-08-30)

**This section supersedes the dispatch in the two sections above. Read all three
in order; the sequence is the point.** frankA's disproof stands and is not in
dispute. What does not follow from it is the inference *I* drew — that the
partial-landing hazard was dissolved. **The guards are inert today and
load-bearing the moment the prologue is fixed, and those two states are
indistinguishable from the source.**

frankC measured both halves, paired, same source, one change: route a `ProcCdecl`
proc's prologue through `EmitParamSpillsForTarget` on i386/arm32/aarch64 instead
of `cparser.inc`'s local positional arms. Baseline `faf762981c3c` → experiment
`e4d7c60f3dab`, both converged in 1 round.

```
Pascal->C bridge          Pure C (C caller -> C callee)
x86-64   6/6  ->  6/6     x86-64   clean -> clean
aarch64  2/6  ->  5/6     aarch64  clean -> dbl_first 0, two_dbl 1.79e308
riscv32  6/6  ->  6/6     arm32    clean -> COMPILE FAIL
i386     0/6  ->  1/6     riscv32  clean -> clean
                          i386     clean -> SEGFAULT
```

The **pure-C baseline was measured, not assumed** — clean on all five — because
otherwise the arm32 compile failure would have read as pre-existing.

### What this establishes

- **The mechanism is `cparser.inc`'s positional prologue arms, not codegen.**
  Fixing them alone takes aarch64's four double shapes and turns i386's `321` into
  `123`.
- **The seven guards do exactly what their comments claim** — they hold C-mode
  call sites positional to match that positional prologue.
- **Delete the arms alone:** every C-to-C call on three targets breaks in order to
  fix the bridge. **Delete the guards alone:** nothing moves — which is precisely
  what frankA measured. **Both halves or neither, in one commit.**

frankC's original conclusion stands; the reasoning it first gave for it was wrong,
and frankA's falsification is what let it find the right one. That is the falsifier
working as intended, not a wasted step.

### The coordinator's error, recorded because the dispatch turned on it

I read "deleting X alone changes nothing" as "X is not part of the fix." It does
not follow. **Deletion tests whether something is load-bearing in the CURRENT
configuration; it says nothing about the configuration after the fix.** A
compensating mechanism is inert exactly while the thing it compensates for is
still broken — that is what makes it a compensation. So the instrument frankA used
was sound and my reading of its scope was not, and I converted that reading
directly into a split dispatch. This is the same confounding as the guard/backend
correlation, one level down: *inert-today* and *irrelevant-after* look identical
from the source, and only the paired experiment separates them.

### Three residues, surfacing only once the prologue is fixed — all Track A

Not in scope for the primary commit; file as a follow-on.

- **aarch64 `f(float,int)` still `0.00`** — Single only; every double came right.
  So it is float **classification** of Single, not argument order.
- **i386 floats still `Nan` across the board** — order fixed, classification not.
- **arm32's shared cdecl arm fails to compile** a plain C program that builds
  fine today. Distinct from
  [[bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area]]; that ticket owns the
  bridge's four-arg refusal, this is the shared arm regressing pure C.

## BLOCKED on the shared arm, and the order of work inverts (frankC, 2026-08-30)

The gate landed first: `test/test_c_abi_pascal_caller.pas` (the red) and
`test/c_abi_pure_c_control.c` (the control), plus `make test-c-abi-cross`, as
`3226a45ff`. Then I applied the whole fix — the three-arm deletion in
`cparser.inc` **and** the seven guards — and measured it. It does not land yet.

**Paired, identical source, `8a42f93ffe74` → `7d91463cbbfc`:**

| target | Pascal→C bridge | pure C control |
| --- | --- | --- |
| x86-64 | PASS → PASS | PASS → PASS |
| aarch64 | 3 fail → **1 fail (`flt` only)** | PASS → **FAIL (`flt`)** |
| arm32 | 1 fail → **PASS** | flt-fail → **COMPILE FAIL** |
| riscv32 | PASS → PASS | flt-fail → unchanged |
| i386 | 5 fail → **order fixed**, floats Nan | flt-fail → **COMPILE FAIL** |

**The C-side change is right** — arm32's bridge goes fully green, aarch64 drops
to Single-only, i386's `321` becomes `123`. **It cannot land yet** because
`EmitParamSpillsForTarget` has three gaps that only surface once something
routes into it: aarch64 mishandles a by-value Single, i386's arm has no float
classification at all, and arm32's cannot compile a varargs-using TU. Filed as
[[bug-a-the-shared-cdecl-spill-arm-cannot-yet-do-the-job-it-would-be-given]],
and this ticket is `blocked-by:` it — so its p65 propagates down the edge.

**Both of us were wrong about the ordering, in opposite directions.** I had the
three residues as follow-ons that surface after the commit; frankA proposed them
as prerequisites and measured the case that settles it. They are prerequisites:
the shared arm has to be able to do the job before it can be given the job.

**And "both halves" was necessary but not sufficient.** frankA tested my
prediction — prologue plus guard deletion should restore pure C — and it does
not. My reasoning was right about the guards being load-bearing and wrong about
them being the only missing piece. Three falsifications in a row on this ticket,
each from the other agent's tree, each correct.

### A correction to the control I committed an hour ago

`c_abi_pure_c_control.c`'s header said it was "green on all five targets TODAY
and must stay green". **False on three of them**: `flt` — a `float` parameter
and `float` return — is already broken on arm32 (`0.00`), riscv32 (`0.00`) and
i386 (`-7.55e307`) with no change applied. I verified only x86-64 before
committing, which is precisely the unmeasured baseline I had criticised twice
today. Corrected in the file and in the Makefile, and filed separately as
[[bug-c-a-float-parameter-and-return-are-wrong-in-pure-c-on-three-targets]] —
**riscv32 is the tell**: this ticket's fix never touches riscv32, and riscv32
fails `flt` today, so the two cannot be the same defect.

The cross rows stay wired as `test-c-abi-cross`, RED by design, not a dependency
of `test`. It is the red that A's prerequisite plus this ticket turn green
together.
