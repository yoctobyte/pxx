---
track: A
prio: 65
type: bug
status: working
blocked-by: []
owner: frankA
summary: "EmitParamSpillsForTarget's ProcCdecl arms have three gaps that only surface once the C frontend routes into them: aarch64 mishandles a by-value Single, i386's arm has no float classification at all, and arm32's cannot compile a varargs-using translation unit. These are PREREQUISITES for bug-c-a-c-function-s-calling-convention-depends-on-the-target, not follow-ons -- routing the C prologue into an arm with these gaps breaks pure C no matter what the call sites do."
---

# The shared cdecl spill arm cannot yet do the job it would be given

Found by frankA and frankC independently, from opposite directions, on
2026-08-30. Split out of
[[bug-c-a-c-function-s-calling-convention-depends-on-the-target]], which is
**blocked on this** — the ordering matters and it is the opposite of what both
of us first assumed.

## Why it is a prerequisite and not a follow-on

The C-frontend fix deletes `cparser.inc`'s positional prologue arms so a
`ProcCdecl` proc's prologue comes from `EmitParamSpillsForTarget` instead. That
is only correct if the shared arm can already do everything the local arms did.
It cannot. **Routing into an arm with these gaps breaks pure C regardless of
what the call sites do** — measured with the call-site guards deleted as well,
so this is not the guards.

## Measured, paired on identical source

Baseline `8a42f93ffe74` → both halves applied (`cparser.inc` arms deleted, the
seven `not CProgramMode` guards removed) `7d91463cbbfc`. Subjects:
`test/test_c_abi_pascal_caller.pas` and `test/c_abi_pure_c_control.c`.

| target | Pascal→C bridge | pure C control |
| --- | --- | --- |
| x86-64 | PASS → PASS | PASS → PASS |
| aarch64 | 3 fail → **1 fail (`flt` only)** | PASS → **FAIL (`flt`)** |
| arm32 | 1 fail → **PASS** | flt-fail → **COMPILE FAIL** |
| riscv32 | PASS → PASS | flt-fail → flt-fail (untouched) |
| i386 | 5 fail → **order fixed**, floats Nan | flt-fail → **COMPILE FAIL** |

The bridge improves substantially — arm32 goes fully green and aarch64 drops to
Single-only — which is the evidence that the C-side change is right. The pure-C
column is what blocks it.

## The three gaps

1. **aarch64: a by-value `Single`.** Every `double` shape comes right; `flt`
   (a `float` parameter and `float` return) gives `0.00` on both subjects. The
   arm's own comment says a by-value single arrives raw in `s[n]` and is stored
   without conversion — the C frontend's value model may be handing it double
   bits instead. Classification of Single, not order.
2. **i386: no float classification.** The order fix lands (`321` → `123`) and
   every float shape stays `Nan` on the bridge; pure C fails to compile with
   `near: unit builtinheap`. The i386 cdecl arm looks like it never handled
   floats, which is invisible today because nothing routes into it.
3. **arm32: a varargs-using translation unit will not compile.** `near:
   overflow nfp ap` on a plain C program that builds fine today. `cparser.inc`'s
   prologue does `__va_save` register-area setup before its target dispatch;
   something in that path does not survive the routing. Distinct from
   [[bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area]], which owns the
   four-core-register argument-block refusal — this one is about a TU that has
   no wide call in it at all.

## Order of work

1. Fix the three gaps here. Pure C must stay clean **with the local arms still
   in place** — nothing routes into the shared arm yet, so it should.
2. Then land the C-side deletion plus the seven guards
   ([[bug-c-a-c-function-s-calling-convention-depends-on-the-target]], frankC,
   claimed). Both tables should go green together.

## Reproduce

`/tmp/frankC-share/abi-probe/` and the two wired subjects above. The cross rows
are `test-c-abi-cross` (RED by design until the pair lands). Note `flt` is
ALREADY red on arm32/riscv32/i386 in pure C before any of this — that is
[[bug-c-a-float-parameter-and-return-are-wrong-in-pure-c-on-three-targets]] and
must not be read as caused by this work.


---

# GAP 1 IS NOT A Single MISHANDLING — the RETURN convention has no counterpart

frankA, 2026-08-30. Measured under the scaffold (cparser routing applied
locally, never committed), compiler shas quoted per run.

## The complementary table that settles it

`fnarrow.c` isolates the two halves: **D** is a `float` parameter with an `int`
return; **C** is an `int` parameter with a `float` return. Both run on aarch64,
same source, one variable changed between the two runs.

| | routing ON, guards PRESENT | routing ON, guards REMOVED |
| --- | --- | --- |
| **D** — float PARAM, int return | **0 — BAD** | **10 — ok** |
| **C** — int param, float RETURN | **10 — ok** | **0 — BAD** |

Exactly complementary. Removing the guards fixes the parameter and breaks the
return; keeping them does the reverse. Nothing here is a `Single`
classification defect.

**The mechanism.** The C-side change routes only the *parameter spill* into the
shared arm. Nothing routes the callee's **return**. So with the guards removed,
the caller takes the AAPCS arm — which, per its own comment at
`ir_codegen_aarch64.inc:2993`, *"bridges a float result d0 -> x0 for the GPR
value model"* — while the C callee's epilogue still returns the float in the
positional model. Caller and callee disagree about where the result lives.

The parameter half was routed; the return half was not. **That is the gap**, and
it is one defect, not the per-target list below.

## What this does to the ticket's own framing

- The "aarch64 mishandles a by-value `Single`" reading is wrong. I tested it
  first, because the arm's comment invited it: I made the cdecl arm narrow with
  `fcvt s0, d[n]` instead of a raw `str s[n]`. **`flt` stayed `0.00`** and the
  change was reverted — the arm's existing comment is correct and states the
  caller already narrows (`fmov d[hi], x9` then `fcvt s[hi], d[hi]`). Recorded
  so nobody re-runs it.
- **i386's "floats stay Nan" is very likely the same defect**, not a separate
  "no float classification": the i386 arm has the identical shape, an st0->xmm0
  result bridge behind the same guard (`ir_codegen386.inc:3646`).
- **Gap 3 is not distinct from
  [[bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area]] after all.** The full
  error, which the ticket quotes only the tail of, is
  `target arm32: a cdecl routine whose argument block exceeds 4 core registers
  is not supported yet`, raised while compiling **`lib/crtl/src/stdarg.c`**. It
  is that ticket's refusal, reached because routing sends a `stdarg.c` helper
  through the shared arm. Not "a TU with no wide call in it".

## Correction to a claim I made earlier in this ticket's history

I reported the pure-C baseline as CLEAN on all five targets and frankC reported
`flt` failing on three. **Both were right about their own control.** Mine routes
the float result through a *prototyped* `chk(const char*, double, double)`;
frankC's hands it straight to variadic `printf`. Isolated on baseline: a float
result assigned to a local and compared in C is correct on all of
x86-64/arm32/riscv32/i386, and only the direct-into-variadic form fails. That is
[[bug-c-a-float-parameter-and-return-are-wrong-in-pure-c-on-three-targets]],
which is also mis-titled — the parameter is fine and the return is fine; the
variadic argument conversion is not.

**Consequence for anyone using these subjects as an oracle:** on
arm32/riscv32/i386 an absolute float row in the pure-C control is reading that
defect, not this one. The *deltas* in the paired table remain valid.

## Where this leaves the work

The prerequisite is bigger than "three gaps in the spill arm" and is not only a
spill-arm change: the C-defined callee's **return** must move to the C
convention at the same time as its parameters, or the two halves will keep
trading places. Whether that lands as a return-side counterpart to
`EmitParamSpillsForTarget` or as part of the C-side commit is the open design
question.
