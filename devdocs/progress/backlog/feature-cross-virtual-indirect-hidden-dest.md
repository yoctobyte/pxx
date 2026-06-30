# Aggregate / frozen-string result via virtual or indirect call — cross backends

- **Type:** feature (codegen — cross targets) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Origin:** the frozen-string reentrancy fix
  ([[bug-frozen-string-result-global-not-reentrant]]) routed frozen-string (and
  aggregate) returns through the hidden caller-destination ABI on **all** call
  paths. x86-64 implements direct + virtual + indirect; the cross backends
  implement **direct only**.

## What's missing

On i386 / arm32 / aarch64, a function returning an aggregate (record/set) or a
frozen string via a **virtual** (`IR_VIRTUAL_CALL`) or **indirect**
(`IR_CALL_IND`) call now errors cleanly:

```
target arm32: aggregate/frozen-string result via a virtual call is not yet
supported (feature-cross-virtual-indirect-hidden-dest)
```

rather than silently emitting a call that never loads the hidden-destination
register → garbage dest → crash. **Direct** calls work on every backend (they
reuse the proven record-return dest path). riscv32 / xtensa don't implement
virtual/indirect calls at all (bare-metal, no OOP), so they're moot there.

## The work

Mirror the x86-64 codegen (ir_codegen.inc): in each cross backend's
`IR_VIRTUAL_CALL` and `IR_CALL_IND` case, when `IRCallDest[node] >= 0`, evaluate
that IR_LEA and load it into the target's indirect-result register **before** the
dispatch — the same register `EmitAggregateDestStash` reads (i386 = ecx,
arm32 = r12, aarch64 = x8). The dest IR_LEA only touches the scratch reg, so the
already-loaded argument registers stay intact (verified on x86-64 with r10).
Remove the clean-error guard once each is wired.

## Why deferred

x86-64 is the tested path (no cross harness exercises a virtual/indirect
frozen/aggregate return — and nested dynarrays already segfault on these targets,
[[bug-nested-dynarray-cross-segfault]]). Writing untested cross codegen for a
niche-within-niche path (cross + frozen/aggregate + virtual/indirect) was held
back in favour of an honest compile error.

## Acceptance

- A virtual and an indirect aggregate/frozen-string return compile + run on
  i386 / arm32 / aarch64 (oracle == x86-64); the clean-error guards removed; cross
  regression tests; self-host byte-identical.
