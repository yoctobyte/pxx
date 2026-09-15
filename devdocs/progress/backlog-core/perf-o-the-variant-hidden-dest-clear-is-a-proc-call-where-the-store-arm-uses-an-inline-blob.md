---
type: perf
track: A
prio: 35
status: open
slug: perf-o-the-variant-hidden-dest-clear-is-a-proc-call-where-the-store-arm-uses-an-inline-blob
---

# The variant hidden-dest clear is a full proc call where IR_VAR_STORE uses an inline blob

`IRBuildHiddenDest` and `IRAppendCall` both clear the variant scratch slot
before a hidden-dest call by emitting `IR_CALL` to `PXXVarClear` with an
`IR_ARG` holding an `IR_LEA` — a real call with argument setup.

`IR_VAR_STORE` and `IR_VAR_BOX` clear their destination with
`IREmitNode(IRA[node]); EmitVariantClear;` — the address in rax and the
`VariantClearBlobAddr` blob, which **preserves rax** (`defs.inc`). No call
frame, no argument node.

The two do the same thing by different means, and the expensive one is on the
hot path: every NilPy method call returns a Variant, so every method call pays
it.

## MEASURED COST, 2026-09-15, interleaved min-of-5 against `pascal26_BOTHFIX`

| program | old | new | |
|---|---|---|---|
| 6M bare method calls, no other work | 1.96s | 2.23s | **+14%** |
| method-heavy with allocation per iteration | 0.84s | 0.91s | **+8%** |

The clear itself is correct and is NOT the thing to remove — it fixes an
unbounded leak (`bug-n-a-method-result-that-rides-the-variant-carrier-leaks-a-reference-per-call`,
closed 2026-09-15). This ticket is only about how it is spelled.

The worst case in the table is the honest one to quote for a dispatch-bound
program, and the 8% row is closer to what real code sees.

## WHAT IT WOULD TAKE, AND WHY IT IS NOT A ONE-LINER

There is no IR kind for "release the variant payload at this address". The
store arms reach `EmitVariantClear` from inside their own codegen arm, where
the address is already in the register. A shared spelling needs either a new
IR kind — and `IRCallDest` is consumed per backend, so every backend needs the
arm — or the clear folded into the existing hidden-dest emission each backend
already does.

**Do not start this by changing one backend.** `gate.sh quick`'s backend-parity
row exists to catch exactly that, and the leak fix it would be optimising was
written in the IR precisely so all six inherit it.

## WHAT WOULD RETIRE THIS TICKET WITHOUT WORK

A measurement showing the clear is cheap relative to the dispatch it rides on
in a REAL program rather than a microbenchmark. Both rows above are synthetic,
and neither says what a demo pays. `lekkerzeilen`'s own leak instrument reports
CPU percentages per leg and would answer it as a side effect.
