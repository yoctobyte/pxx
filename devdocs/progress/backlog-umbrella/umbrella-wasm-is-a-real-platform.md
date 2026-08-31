---
slug: umbrella-wasm-is-a-real-platform
title: "wasm as a real platform — emit it, and host the compiler on it"
track: A
prio: 70
type: umbrella
blocked-by: [feature-target-wasm, bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime-on-a-full-compile, feature-t-run-the-wasi-slices-under-wasmtime-as-a-strict-second-host, bug-a-emitzeroframeslot-has-no-wasm32-arm]
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
