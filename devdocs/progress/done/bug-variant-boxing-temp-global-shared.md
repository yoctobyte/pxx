# Variant-boxing temporaries are shared globals (thread-unsafe)

- **Type:** bug (latent, thread-safety) — Track A (IR lowering)
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** thread-safety audit alongside
  [[bug-frozen-string-result-global-not-reentrant]].

## Symptom

When a variant comparison/operation needs to box a non-variant operand, the IR
lowering allocates the box temp as a **program global**:

```pascal
{ ir.inc, variant operand boxing (two sites) }
savedProc := CurProc;
CurProc := -1;                       { force global scope }
value := AllocVar('', tyVariant);    { one shared BSS slot per source site }
CurProc := savedProc;
left := IRAppend(IR_VAR_BOX, IRAppend(IR_LEA, value, ...), ...);
```

So every runtime execution of that comparison site writes the same BSS slot. Two
threads evaluating the same site race on it. (Single-threaded is safe: the box and
its use are in one expression with no intervening call, so recursion does not
clobber it — unlike the frozen-string Result, this is thread-only, not a
reentrancy bug.)

## Fix

Allocate the variant box temp as a routine **local** (the normal `CurProc >= 0`
path) instead of forcing global scope, so each call/thread gets its own slot. The
`CurProc := -1` here looks like a copy of the frozen-string-Result idiom and is
probably unnecessary — a stack local works for a transient box. Verify the temp's
lifetime does not outlive the frame (it is consumed within the comparison, so a
local is fine). Keep self-host byte-identical (variants are rare in the compiler's
own source) + cross green.

## Acceptance

- Variant boxing temps are routine-locals; no shared global box slot.
- A threaded variant-compare test does not race (once the thread runtime lands).
- Self-host byte-identical; cross green.

## Notes

- Part of the thread-safety cluster: [[feature-threadsafe-io-serialization]],
  [[feature-threadsafe-heap-contract]], [[bug-frozen-string-result-global-not-reentrant]].

## Resolution (2026-06-30, commit a7d5d413, pin v97)

Fixed. Dropped the `savedProc := CurProc; CurProc := -1; ... := savedProc`
forcing at both variant-operand-boxing sites in `ir.inc`; the box temp is now a
plain `AllocVar('', tyVariant)` routine-local (per-call/thread slot). It is
consumed within the one comparison and never outlives the frame, so a local is
correct. `savedProc` removed (now unused). Single-threaded behaviour unchanged.

Verified: self-host byte-identical; `make test` + all four cross suites
(i386/arm32/aarch64/riscv32) green — `variant` + `variant-single` output
identical to x86-64. The arithmetic-result variant temp (separate BSS slot at the
non-comparison branch) is a different allocation and out of scope here; it is a
transient result, not an operand box.
