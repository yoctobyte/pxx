---
track: U
prio: 30
type: decide
status: open
found: 2026-08-29
found-by: frankD
summary: "ir_codegen.inc:10036 calls RcProcHasExc 'the gate that stands today' and :10100 says anything that stops keeping the slot current 'must refuse a body that has one'. Both RcProcHasExc and the finer SymWrittenInProtectedSpan are consumed ONLY by a PXXDBG WriteLn — neither appears in any condition. Either the gate is unbuilt and the correctness rests entirely on the landing-pad refresh, or the comments describe an intent that was never wired. I cannot tell read-only, and the code is from today."
---

# The -O3 residency exception "gate that stands today" is only a debug print

Found by the invariant sweep
([[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]]),
pass 5. **Filed as a Track U question, not a bug** — I could not settle it
read-only and the code landed today, so guessing at intent is the wrong move.

## What the comments say

`compiler/ir_codegen.inc:10100-10101`:

> *"the exception landing pad refreshes residents FROM their frame slots, so it
> is the one slot reader that residency cannot see through. **Anything that stops
> keeping the slot current must refuse a body that has one.** Conservative
> default is True."*

`compiler/ir_codegen.inc:10035-10036`:

> *"This is the axis the -O3 item-3 gate actually turns on, and it is finer than
> **the `RcProcHasExc` gate that stands today.**"*

## What is measured

`RcProcHasExc` appears at exactly four sites:

| line | use |
| --- | --- |
| 10036 | the comment above, calling it a gate that stands |
| 10102 | `RcProcHasExc := False;` |
| 10104 | set True when an `IR_EXC_ENTER` is found |
| 10261 | `' exc=', Ord(RcProcHasExc),` — inside `if PxxDbgEnabled('a.resid')` |

`SymWrittenInProtectedSpan` — the *finer* axis the first comment says the gate
"actually turns on" — appears at four sites too: its own declaration (10066), two
lines of its own body, and **10262, the next argument of the same `WriteLn`**.

**Neither symbol appears in any `if`, any `Exit`, or any assignment that reaches
codegen.** The residency assignment's real early-exits are `OptLevel < 3`,
`CurProc < 0`, `RcSuppressAssign`, `TargetArch <> TARGET_X86_64`,
`CurProcIsGenerator or CurProcIsStackless`, and `IR_ASM` — no exception test
among them.

## The two readings, and why I am not choosing

1. **No gate is needed.** The header at 10024-10032 lists the landing refresh as
   one of the choke points: *"the IR_EXC_ENTER landing refresh covers the longjmp
   rollback"*. If that refresh is unconditionally correct, residency needs no
   refusal, both symbols are pure instrumentation for the *next* slice, and the
   defect is only that 10036 says a gate "stands today" when it does not.
2. **A gate is needed and is not there.** 10100's *"must refuse a body that has
   one"* is written as a live requirement in the imperative. If it is, an -O3
   x86-64 body with a `try` currently gets residency with no refusal, and
   correctness rests entirely on the refresh being complete.

Reading 1 is more likely — the surrounding prose reads like a designed
instrumentation step ahead of "item 3" — but *"the gate that stands today"* is
not a phrase you write about a debug print, and I would rather ask than assume.

## What I am asking

**Is the `RcProcHasExc` / `SymWrittenInProtectedSpan` pair instrumentation ahead
of a gate, or a gate that was never wired?**

- If instrumentation: fix 10036 (`the gate that stands today` → say plainly that
  nothing gates on exceptions yet and the landing refresh is what carries
  correctness) and soften 10100's imperative to describe the requirement on a
  *future* slot-reader rather than on today's code.
- If a missing gate: it is an -O3 correctness bug on x86-64 bodies containing a
  `try`, and it should be re-filed as `bug-a-*` in Track A with a repro built
  from `test_o3_resident_exc`'s MIX case, which the comment already names.

`e967f90387` (10036) and `d2eafe1e39` (10100) are both from **2026-08-28/29** —
hours old at filing — so this is in-flight work and its author will answer in
seconds what I could not settle in an hour of reading.

## Why the audit flags it at all

It is the sweep's shape with the arms one level apart: **a comment asserting that
an enforcement exists, and the enforcement being a print statement.** The phrase
*"the gate that stands today"* is a claim about the state of the code, adjacent
to the code, and the code does not support it. Whether it is a documentation slip
or a real hole, that sentence is the reason nobody has checked which.

## Gate

None — this is a question. Whatever it resolves to takes Track A's gate.
