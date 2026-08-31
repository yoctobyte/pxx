---
slug: bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds
track: A
prio: 30
type: bug
status: new
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "The C half of bug-a-aarch64-has-no-stack-argument-passing-for-five-of-six-call-kinds, which fixed the four pxx-internal call kinds and measured that the other three are a DIFFERENT mechanism. External, variadic external and cdecl indirect calls still refuse past 8 parameters, because AAPCS64 allocates integer/pointer args from x0..x7 and FP args from v0..v7 as INDEPENDENT banks with a per-parameter classification -- not the internal convention's every-arg-is-8-bytes-in-an-x-register-by-position. Nothing reaches it today: no external we call declares more than 8 params."
---

# aarch64: no stack-argument passing for the three C-ABI call kinds

- **Filed:** 2026-08-31 by frankA, on fixing the internal four. Original finding
  frankS's.
- **Nothing reaches this today.** It is filed because the parent ticket claimed
  one mechanism refused six times, and that is not what the code says.

## The three sites, `compiler/ir_codegen_aarch64.inc`

| kind | guard |
| --- | --- |
| external call | `Procs[procIdx].ParamCount > 8` |
| variadic external call | `nArgs > 8` |
| cdecl indirect call | `nArgs > 8` |

There is a fourth, adjacent guard — `(lo > 8) or (hi > 8)`, "exceeds 8 int or 8
fp argument registers" — which is about one BANK overflowing and is the same
defect seen from the other side.

## Why the internal helper does not answer it

`EmitCallArgRegsA64` assigns register `i` to argument `i`. AAPCS64 for C does
not: it classifies each parameter and draws from two independent banks, so
argument 3 can be `d0` and argument 4 `x3`. A by-REF float counts as a POINTER
and belongs in the integer bank — the x86-64 twin of that line once put
`var d: Double` in an SSE register while the callee read a pointer from a GPR,
which is `bug-a-a-by-ref-float-param-through-a-cdecl-fnptr-is-classified-sse`
and was a segfault rather than a wrong number.

## What it owes before anyone starts

AAPCS64's stack rule is not "the ninth argument onward": it is NSAA, and once an
argument is placed on the stack the banks are considered exhausted for the rest
of the call, with per-type alignment of each stack slot. Getting that wrong is a
crash at a library boundary, which is why this is parked rather than
approximated.

Verify against the gcc oracle (`tools/gcc_diff_probe.sh --target=aarch64`), not
against our own second implementation.
