---
track: O
prio: 35
type: feature
summary: "A non-const open-array VALUE parameter now copies on every call — correct, and 6.4x on a hot path where FPC pays 2.4x. pxx's copy is ~20x more expensive per call than FPC's (heap dyn-array alloc + refcount vs whatever FPC does). Worth a look before anything hot relies on it."
---

# The copy a by-value open array now pays, and why FPC's is cheaper

- **Type:** feature — **Track O** (optimization; file-owned by Track A, obeys
  A's gate — `ir.inc` / `parser.inc`).
- **Opened:** 2026-08-07, out of
  [[bug-a-open-array-value-parameter-aliases-instead-of-copying]], which made
  the copy exist. **Nothing here is a defect** — the semantics are now FPC's and
  verified byte-identical against it. This is about what the correct answer
  costs.

## Measured

3,000,000 calls of a routine summing a 64-element open array (256 bytes copied
per call when the parameter is not `const`), x86-64, `-O2` both sides, best of
three:

| | FPC | pxx |
| --- | --- | --- |
| `const x: array of Integer` (no copy) | 0.09 s | 0.47 s |
| `x: array of Integer` (copies) | 0.22 s | 3.02 s |
| **what the copy costs** | **+0.13 s (2.4x)** | **+2.55 s (6.4x)** |
| per call | ~43 ns | ~850 ns |

Both compilers copy — that part is the semantics, and pxx is not wrong to pay
it. What stands out is the **~20x gap in the cost of one copy** of 256 bytes.

## The likely cause, and it is NOT yet measured

pxx spells the copy as `AN_DYN_COPY`, the same node `Copy(a)` builds: a fresh
**heap** dynamic array — `PXXAlloc`, a refcount word, a length word, then the
element copy, then a scope-exit `PXXDynArrayRelease`. That is a malloc/free pair
per call for a value that cannot outlive the call.

FPC almost certainly puts the copy on the **stack** (a value open array is
dead at return, so it needs no heap and no refcount). **That is a hypothesis, not
a measurement** — check it by disassembling FPC's callee before building
anything on it. It is exactly the shape of assumption this repo's debugging
playbook says to verify against the oracle rather than reason about.

## Options, roughly in increasing order of ambition

1. **Stack-allocate the copy.** The natural answer if FPC's is on the stack. The
   length is a run-time value, so this wants an alloca-shaped facility pxx does
   not have today; a bounded-size fast path with a heap fallback is the cheaper
   half-step.
2. **Copy-on-write.** Pass the handle with an incref and let the callee's first
   element WRITE call the existing `PXXDynArrayUnique`, which already does
   exactly "duplicate if shared" including element retain. Free on the read
   path — which is the overwhelmingly common one — and pays only where a write
   actually happens. Note `ir_codegen_xtensa.inc` / `ir_codegen_riscv32.inc`
   already carry the comment *"(No COW / by-ref open arrays yet.)"*, so this is
   a recognised absent concept rather than a new invention. Cost: a write
   barrier on element stores to such a parameter.
3. **Write-detection.** Skip the copy entirely when the callee never writes the
   parameter. Rejected once already for the *correctness* fix — `const` is the
   programmer-declared version of the same thing and needed no analysis — but as
   an OPTIMIZATION over code that did not say `const`, it is a legitimate pass.
4. **A hint.** Emit an advisory when a by-value open array is never written in
   the callee, suggesting `const`. Cheapest of all, and it teaches the idiom
   that makes the cost go away — FPC's own advice.

## Why the priority is 35 and not higher

Nothing reaches this path today. Every one of the 29 open-array parameters in
the compiler's own source is `const` (one is `var`), so self-host and the whole
corpus are unaffected — measured as part of the fix, and the reason it could
land without a perf regression. This becomes real the first time an application
passes a large array to a non-`const` open-array parameter in a loop.

## Not this ticket, but found by the same benchmark

The **`const` baseline itself is ~5x slower than FPC** (0.47 s vs 0.09 s for
192M sum-loop iterations — ~2.4 ns/iter vs ~0.47 ns/iter). That is ordinary
loop-and-index codegen with no copy anywhere in it, it reproduces on `pinned`,
and it has nothing to do with open-array parameters. Recorded here only so the
number above is not misread as this ticket's fault; it deserves its own Track O
ticket, and probably a wider benchmark than one hand-written loop before anyone
concludes anything from it.

## Gate

Whatever lands: the FPC differential in
`test/test_open_array_value_param_copies.pas` stays byte-identical (the
semantics must not move), plus a before/after of the benchmark above, plus the
`const` path shown unchanged.
