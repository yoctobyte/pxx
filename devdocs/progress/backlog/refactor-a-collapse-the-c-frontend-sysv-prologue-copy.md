---
track: A
prio: 60
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


---

# UPGRADED 2026-08-30: this is the ROOT CAUSE of a five-red incident, not tidiness

Filed as a duplication smell. It is more than that. `cparser.inc` does not have
*one* prologue spill with a copy — it has **three per-target spills that disagree
with each other about which convention a C function uses**:

| target | cparser's prologue spill | so a C function is... |
| --- | --- | --- |
| x86-64 | `cparser.inc:11282` — genuine SysV, independent int/SSE counters | **C-ABI** |
| aarch64 | `cparser.inc:11178` — positional, *"mirrors the Pascal aarch64 spill"* | **internal** |
| arm32 | `cparser.inc:11128` — positional, word-based | **internal** |

**A C function's calling convention therefore depends on the target**, and
nothing names that fact in one place. Every call site that wants to know "is this
proc reached by the C ABI?" has to encode the answer per target, and it is not
the same answer.

## What that cost

`bug-a-a-c-mode-function-took-the-cdecl-call-path-on-aarch64-and-arm32` — five
p70 NEW-REDs (four `test-c-conformance-aarch64` shards and `test-lua-cross`).
`ProcExternal[p] or ProcCdecl[p]` is **correct on x86-64 and wrong on
aarch64/arm32**, purely because of the table above, and the same expression had
already been paid for once at `b362` on the indirect arm.

The `and (not CProgramMode)` guards now present on the aarch64 and arm32 call
arms are **compensating for this table**. They are correct, and they are a
workaround: they exist to stop a C-mode callee being called by a convention its
own prologue does not implement. Collapse the spills onto
`EmitParamSpillsForTarget` and C functions use one convention per target *by
construction*, the guards describe something real instead of patching something
accidental, and `ProcCdecl` means the same thing everywhere.

Three strikes on this predicate so far: `b362` (indirect, lua + sqlite),
`eeb51710e` (aarch64 direct), `6d2939f38` (arm32 direct).

## Sequencing note

`EmitParamSpillsForTarget` now has C-ABI arms for x86-64, aarch64 and arm32 (from
`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets`),
so the shared destination for the collapse **already exists on three of five
targets** and grows as that campaign finishes. Doing this after that campaign is
cheaper than doing it now, and doing it at all is what stops strike four.

Still blocked on `cparser.inc` being held by the csmith campaign.
