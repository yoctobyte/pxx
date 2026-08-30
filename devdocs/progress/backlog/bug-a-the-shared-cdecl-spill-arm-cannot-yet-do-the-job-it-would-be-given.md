---
track: A
prio: 65
type: bug
status: new
blocked-by: []
owner: ""
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
