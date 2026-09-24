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
summary: "ONE CLASS IS CLOSED (2026-09-24): a missing RTL HELPER is no longer a floor -- WasmRuntimeHelper fails the build (rc=1), because a helper the lowering calls into being absent is a unit the build forgot, not a construct this backend cannot lower (`writeln(6*7)` built `ok:` and trapped). What stays open is the policy for a genuine lowering gap. A variadic CALL on wasm32 writes a valid 117KB module, prints `ok:` and exits 0 with `main` lowered to `unreachable` — a GREEN BUILD OF A PROGRAM THAT TRAPS ON ITS FIRST INSTRUCTION. The `unreachable` floor is the wasm backend's own partial-lowering instrument and is correct as a floor; what is unowned is its EXIT-CODE POLICY. Blast radius measured, not estimated: re-measured at origin `54b2cf4d9` / compiler `8f8a089c6812` over a STATED population of 43 sources (`test/wasm/*.pas` + `test/*wasm*.pas`): 43 reached the backend, 42 clean, 0 invalid, and EXACTLY ONE emits a gap — the test that exists to document the mechanism, whose unreachable body is `main$0`, so a naive 'fatal when the entry traps' rule would red that test. So this is not a one-line policy flip and that is why it is filed rather than fixed."
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

**RE-MEASURED 2026-09-19 (frankB), and the claim HOLDS — but read the
population line before quoting either number.**

| census | tree | population | result |
| --- | --- | --- | --- |
| original (frankb-56) | **not recorded** | **not recorded**, "61 wasm32 sources" | 59 clean, 1 unrelated failure, 1 gap |
| re-run | compiler `8f8a089c6812`, origin `54b2cf4d9` | `test/wasm/*.pas` + `test/*wasm*.pas`, **43 sources**, listed by `tools/wasm32_gap_census.sh` | 43 reached the backend, 42 clean, **1 with gaps**, 0 invalid, 0 failed before codegen |

**The load-bearing half is re-confirmed at HEAD.** The single gap is
`test/test_wasm32_two_gaps_in_one_body.pas` — the documentation test — and its
unreachable body is `main$0`:

```
wasm32: 139 of 140 bodies lowered; 1 emitted as `unreachable`; 2 distinct gap(s) seen
    main$0 — string operand of type Pointer
        and also — `=` on strings
```

So a naive "fatal when the entry traps" rule still reds exactly this test and
nothing else. That argument is unchanged and is the reason this is filed rather
than fixed.

**WHY THE TWO ROWS DO NOT RECONCILE, AND IT IS NOT A CHANGE IN THE TREE.** The
original number cannot be reproduced, because the ticket recorded the COUNT and
not the SET. 61 is not reachable from any definition I can construct: the .pas
population is 43, adding `.npy` and `.c` reaches 47, and `test/wasm/*` is 98
once the shell scripts are counted. The original census presumably reached
sources outside `test/`, and nothing here says which — so its "1 unrelated
failure" has no denominator anyone can re-derive either.

Both numbers are true of what they measured, and neither may be quoted without
its population. The re-run's is one line above and the tool prints its own
denominator on every run for exactly this reason (see its header: a rate needs
its denominator printed beside it, every time).

**What would retire this table:** the wasm32 population changing — a new
`test/wasm/*.pas`, or the documentation test being renamed or removed. Re-run
`tools/wasm32_gap_census.sh <out> <list>` and replace the second row with its
own sha; do not edit the first, which is a record of a different measurement.

## Not to be confused with

`bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime-on-a-full-compile` —
that is a runtime disagreement between hosts. This is the build reporting
success for something no host can run.

## 2026-09-24 (frankS): the missing-helper class is fatal now

`program t; begin writeln(6*7); end.` built `ok:` rc=0 and trapped under
wasmtime on pin v423 and HEAD `448395e492db` (frankd-a3): `main$0 -- RTL helper
PXXWriteDecW not found`. Two fixes. First, a wasm32 program that writes now pulls
builtinheap (`pasparser_prog.inc`, the riscv32/xtensa write arm). Second,
every wasm32 RTL-helper lookup (the PXXWrite* family, PXXAlloc, PXXFree,
PXXStrFromLit) goes through `WasmRuntimeHelper`, which calls `Error`. The
documentation test's gaps are lowering gaps, not helpers, so it is unaffected.
Census at HEAD, `test/wasm/*.pas` + `test/*wasm*.pas`, 44 sources: 43 clean, 1
with gaps, 0 invalid.
