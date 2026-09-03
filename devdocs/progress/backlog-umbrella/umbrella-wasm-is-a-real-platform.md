---
slug: umbrella-wasm-is-a-real-platform
title: "wasm as a real platform — emit it, and host the compiler on it"
track: A
prio: 25
type: umbrella
blocked-by: [feature-target-wasm, bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime-on-a-full-compile, feature-t-run-the-wasi-slices-under-wasmtime-as-a-strict-second-host, bug-a-emitzeroframeslot-has-no-wasm32-arm, bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps]
created: 2026-08-31
summary: "GOAL, not a unit of work. wasm is named in the goal's platform list and is the non-Unix platform with the most work already landed -- the wasm branch is merged into master. Two halves: emit correct wasm32, and HOST the compiler under a wasm runtime. The hosted half already has a live crash (node, not wasmtime)."
---

# wasm as a real platform

Named in the owner's platform list alongside linux/bsd/minix/gnu/windows. It is
the furthest along of the non-Linux cells: the `wasm` branch is fully merged
into master (verified 2026-08-31).

Two halves, and the second is the one that counts for the goal:

1. **Emit** correct wasm32 from the shared IR.
2. **Host** the compiler under a wasm runtime — the "minimal system with
   compiler" property, on a platform with no processes and no syscalls.

The hosted half already has a concrete failure wired here: the hosted compiler
crashes node but not wasmtime on a full compile, which is a genuine divergence
between runtimes rather than a missing feature.

Full goal: `devdocs/dev/the-goal-cross-cross.md`.

## The gap census, 2026-09-03 - attempted, not triaged

300 sources from the test corpus, compiled for wasm32 with the fixed coverage
report (52d134518), which is the first build whose listing can name more than
one gap per body. 14 programs have a broken body; 278 gap instances behind them:

| count | gap |
| --- | --- |
| 222 | `statement IR op 43` -- **IR_VAR_STORE**, the whole Variant family |
| 18 | `value IR op 54` -- IR_SYSCALL (raw syscalls; wasi has none) |
| 8 | `value IR op 33` -- IR_SET_LIT |
| 7+ | `slot <n> has no wasm value type` |
| 3 | `builtin SetLength (-102)` |
| 3 | `builtin FreeMem (-46)` |
| rest | one or two each: IR_SET_BINOP, IR_RTTI_REG, record loads, `=` on strings |

**Variant is not one of several gaps, it is four fifths of them**, which is why
`bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps` is wired
in here. This is an umbrella grown by ATTEMPTING the target: the ranking came
out of compiling real programs, not out of reading the backlog.

Scope limit: 278 is a FLOOR by construction -- a body stops at its first refusal
-- so the tail is understated relative to the head. It cannot overstate op 43.
