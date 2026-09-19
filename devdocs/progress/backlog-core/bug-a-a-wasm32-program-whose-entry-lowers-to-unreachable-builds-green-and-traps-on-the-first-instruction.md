---
slug: bug-a-a-wasm32-program-whose-entry-lowers-to-unreachable-builds-green-and-traps-on-the-first-instruction
track: A
type: bug
prio: 55
status: backlog
owner: ""
created: 2026-09-19
found-by: frankb-56
tags: [wasm32, backend, silent-negative]
blocked-by: []
summary: "A variadic CALL on wasm32 writes a valid 117KB module, prints `ok:` and exits 0 with `main` lowered to `unreachable` — a GREEN BUILD OF A PROGRAM THAT TRAPS ON ITS FIRST INSTRUCTION. The `unreachable` floor is the wasm backend's own partial-lowering instrument and is correct as a floor; what is unowned is its EXIT-CODE POLICY. Blast radius measured, not estimated: of 61 wasm32 sources, 59 clean, 1 unrelated failure, and EXACTLY ONE emits a gap — the test that exists to document the mechanism, whose unreachable body is `main$0`, so a naive 'fatal when the entry traps' rule would red that test. So this is not a one-line policy flip and that is why it is filed rather than fixed."
---

# A wasm32 build says `ok:` for a module that cannot execute one instruction

Found 2026-09-19 by frankb-56 while measuring the wasm32 walls for
`bug-c-hosted-c-on-wasm32-needs-environ-and-va-arg-...`. **It deliberately did
not change it**, calling it a topic collision rather than a doubt: the floor
belongs to the wasm backend and so does the policy.

## Why this is the expensive class and not a cosmetic exit code

It is the **silent-negative** shape this repo keeps paying for: the compiler
answers correctly about **what it emitted** and says nothing about **whether it
can run**. Same family as the xtensa signal stub that compiled, installed,
returned 0 and dropped every delivery (`92d2967ad`), and as the full-disk short
write that printed `ok:` with exact byte counts for a truncated binary. **Every
cheap instrument passes**: the module is valid, the writer succeeded, rc=0.

## The fork, and why it is not a one-liner

`unreachable` as a partial-lowering floor is **right** — it keeps the backend
landing incrementally instead of on a branch. The question is only what the
DRIVER should report when the floor is reached **in the entry point**.

The obvious rule — *fatal when the entry traps* — **reds the one test that
exists to document the mechanism**, because that test's `unreachable` body IS
`main$0`. Any fix has to separate "a gap the author intended to demonstrate"
from "a gap that silently shipped", and nothing in the emitter records intent
today.

## Measured population, so nobody re-derives it

61 wasm32 sources: **59 clean, 1 unrelated failure, 1 emitting a gap** — and
that one is the documentation test. So the live blast radius of getting this
wrong in either direction is one row, which makes it cheap to attempt and easy
to attempt wrongly.

## Not to be confused with

`bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime-on-a-full-compile` —
that is a runtime disagreement between hosts. This is the build reporting
success for something no host can run.
