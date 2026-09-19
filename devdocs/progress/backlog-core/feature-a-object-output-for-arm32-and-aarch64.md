---
track: A
prio: 45
type: feature
status: backlog
found: 2026-08-31
found-by: frankC
owner: ""
blocked-by: []
summary: "arm32 and aarch64 still have no object writer; i386 landed separately and x86-64 before it. Both are DIVERGENT targets on the C-ABI question, so each one is a second and third oracle for a ruling the i386 measurement has already made once -- worth having, not urgent. aarch64 is gated on an ABI question first: cparser.inc's aarch64 param spill is POSITIONAL while pxx's external-call path is AAPCS, and the two coincide for every all-integer/pointer signature, which is why libc callbacks work today and prove nothing. Make that spill AAPCS, or establish by measurement that it already is, BEFORE landing the writer -- the writer is what makes the falsifying test (a genuinely external caller, mixed int/float) constructible for the first time. Expect the shape to follow i386's, not the ESP writer's: check how each backend reaches an external before assuming."
---

# Object output for arm32 and aarch64

Split out of [[feature-a-object-output-for-i386-arm32-and-aarch64]] when its
i386 half landed. They share no code with it, and one of them is gated on an ABI
question, so carrying them alongside a finished writer would have parked it.

## Do the ABI question on aarch64 FIRST

The trip-wire in
[[feature-a-a-general-x86-64-relocatable-object-writer]] is the reason. On
aarch64 a pxx-compiled **C** function's prologue is positional, while pxx's own
external-call path is AAPCS. They **coincide for every all-integer/pointer
signature**, which is exactly the shape of every standard libc callback — so
`qsort`, `bsearch`, `pthread_create` and `signal` handlers work today and are
*not* evidence. They diverge on mixed int/float, because that is where AAPCS's
independent GP and FP counters stop tracking the argument index.

An object writer is what makes the falsifying test constructible: a genuinely
external caller, with a mixed int/float signature. So the honest order is —
land the writer behind, or immediately followed by, that test, and be ready for
it to go red. **The i386 measurement says to expect exactly that**: with
`CProcUsesCAbi` false, i386 reversed its integer arguments and returned `-nan`
for every double.

## What to reuse, and the one thing to check before assuming

Reuse `ObjPlanHostedSymbols` — the export policy is shared across every hosted
object writer on purpose, so a new target cannot drift from the two that exist.

**Check how the backend reaches an external before writing a line.** That was
the one thing the i386 ticket got right in advance and the ESP writer gets
differently: xtensa and riscv32 relocate a `.text` literal directly against the
extern, while x86-64 and i386 go through a GOT slot in their own `.data` and
need two relocations. arm32 uses a `movw/movt` pair loaded with the slot's
address (`elfwriter.inc`'s ELF32 `DynCall` loop), and aarch64 a `movz/movk`
pair — **neither is a plain 32-bit operand**, so both need a relocation form
this codebase has not emitted yet (`R_ARM_MOVW_ABS_NC`/`MOVT_ABS`,
`R_AARCH64_MOVW_UABS_G0_NC`/`G1_NC`). That is the real work here, and it is why
these two are not a copy of the i386 writer.

Also settle REL vs RELA per target: i386 needed SHT_REL, x86-64 and the ESP
targets use SHT_RELA. arm32's psABI is REL; aarch64's is RELA.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]
