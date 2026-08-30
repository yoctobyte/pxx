---
track: A
prio: 40
type: refactor
status: open
found: 2026-08-30
found-by: claude-A
---

# There are now TWO SysV prologue emitters; collapse `cparser.inc`'s into the shared arm

`EmitParamSpillsForTarget` (`compiler/ir_codegen.inc`) exists precisely to be the
one place a frontend gets its incoming parameters homed. Its own header comment
records why: NilPy's `PyEmitParamSpills` and Rust's `REmitParamRegSpill` were
private raw-x86-64 copies, and a NilPy or Rust program built for a cross target
spliced x86-64 bytes into an ARM instruction stream and SIGILLed. Both copies
were absorbed. `pyparser.inc:19066` still carries the tombstone.

**The C frontend's copy was never absorbed.** `cparser.inc:11282` has a full SysV
classification — independent int/SSE counters, stack overflow from `[rbp+16]`,
`tySingle` narrowing — because C needed a SysV prologue before the shared layer
existed and the shared layer only spoke the internal convention.

`feature-cdecl-bodied-sysv-prologue` has now added a SysV arm to
`EmitParamSpillsForTarget`, mirrored from that C code deliberately rather than
reinvented. So the count went from one copy to two. That is the wrong direction,
and `devdocs/dev/normalise-dont-special-case.md` is explicit about which way it
should go: the second path is the one that stays broken.

**Why it was not done in the same change:** `cparser.inc` was held by another
agent (the csmith campaign) at the time. Sequencing, not disagreement.

## The work

Have the C function-body emitter call `EmitParamSpillsForTarget` and delete the
inline classification at `cparser.inc:11282`. Then a bug fixed in one is fixed in
both, which is not true today.

Two things to preserve, both load-bearing:

- The variadic register-save prologue and the `__va_overflow` anchor are C-only
  and interact with this homing (`ProcNamedGP` / `ProcNamedFP` seed `va_start`'s
  `gp_offset`/`fp_offset`). They must not be flattened into the shared arm.
- The C arm reads declared types from a local `ptypes[]`; the shared arm reads
  `Syms[idx].TypeKind`. Confirm they agree for every C parameter shape before
  swapping — a C declaration can carry a type the symbol does not.

## Gate

`make compiler/pascal26` + byte-identity of the C corpus against the pre-change
binary, built at one HEAD. The collapse should change **no** emitted byte; if it
does, the two copies had already drifted, and that divergence is the real finding
and deserves its own ticket.
