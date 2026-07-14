---
prio: 75
---

# `case` evaluated its selector expression ONCE PER LABEL, not once

- **Type:** bug (silent wrong behaviour — side effects, not values)
- **Track:** A — core (`case` lowering, ir.inc)
- **Status:** RESOLVED 2026-07-14, commit 9f6122e2 (b346). Filed after the fact as the
  record — found by clustering Track T's fuzz reports, not from a ticket.

## The defect
`case` lowers to a COMPARE-CHAIN, and the selector's IR value node was handed to every
label test as an operand. A value node is not a register — it is a subtree, and each
backend re-**emits** it per use. So the selector ran once per label ELEMENT (a range
costing two), stopping at the first match:

```pascal
n := 0;
case f mod 3 of        { f increments n }
  0: ; 1: ; 2: ;
else ; end;
writeln(n);            { pxx: 3.  FPC: 1. }
```

Pascal requires the selector to be evaluated exactly once.

## Why it survived
**The result was always right.** Only the side effects were wrong — so nothing failed, no
value was corrupted, and any test that checked an answer passed. And it disappeared
whenever the FIRST label matched, which is the case everyone writes by hand. The cost
scaled with how far down the chain execution walked, so the worst case was a `case` that
fell through to `else` — the one nobody inspects.

Real-world blast radius beyond the fuzzer: any `case F(x) of` where F has side effects, or
is merely expensive, ran F up to N times.

## How it was found — the fuzzer had been shouting for a day
Track T's pasmith differential fuzzer had filed **527 divergence reports** against FPC (391
at a single SHA). They were ALL this one bug. The generated programs call a checksum `Mix()`
from every function, so a re-evaluated selector mixes extra values: the final checksum
drifts while every global still agrees — which is exactly the fingerprint every report
showed ("globals agree at the checkpoint, only cs differs").

Nobody had clustered them, so the signal read as "hundreds of unknown bugs" instead of
"one bug, reported hundreds of times".

## Fix
Materialise the selector into a temp; compare the temp. Skipped when the value node is
already pure and free to re-emit (`IR_LOAD_SYM` / `IR_CONST_INT` / `IR_CONST_STR`), so the
common `case i of` keeps byte-identical codegen. `IR_LOAD_MEM` is deliberately NOT treated
as pure — its address subtree can contain a call.

## Verification
Re-ran 40 seeds sampled from the reported corpus: **37 now match FPC byte-for-byte.** The
other 3 are not compiler bugs — see [[bug-t-pasmith-order-dependent-programs]].

`test/test_case_selector_single_eval.pas` counts EVALUATIONS rather than checking a result,
because the result was never the thing that was wrong. All four arms (first label, list,
range, no-match-to-else) plus a string selector.

## Gate
`make test` green, self-host byte-identical (one reseed — codegen changed), i386 / aarch64 /
arm32 / riscv32 green.
