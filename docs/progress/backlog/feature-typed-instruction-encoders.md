# Typed instruction encoders for codegen

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-11 (user request)

## Motivation

Backend codegen currently emits raw bytes/words/quadwords directly, with
comments documenting the intended machine instruction. That works, but every
new backend feature repeats operand packing, branch displacement encoding, and
bitfield composition at the call site. The next queued work adds more of that
surface area: cross exceptions, cross float/Variant support, full parameter ABI,
and later targets such as RISC-V / ESP32-class MCUs.

Introduce small typed instruction encoders so new codegen emits through tested
helpers instead of hand-rolled byte math. This is advised, but not blocking:
there is no functional change by itself, and existing working emission should
not be rewritten as a standalone cleanup sprint.

## Scope

- Add ARM-family encoder helpers first:
  - `a64enc.inc` for AArch64 fixed-width instruction forms.
  - `a32enc.inc` for ARM32 fixed-width instruction forms.
- Keep helpers small and typed around actual emitted forms, for example
  register arithmetic, loads/stores, branches, compare-and-branch, calls, and
  immediate/materialization patterns used by the backend.
- Prefer pure `Integer -> Integer` / `NativeUInt -> NativeUInt` instruction-word
  builders for ARM where possible, with `EmitI32(A64_...)` style call sites.
- Add focused encoding tests that assert exact instruction words/bytes for
  representative forms and boundary cases.
- Later, factor common x86-64/i386 forms from `asmenc.inc` into a reusable
  encoder core shared by codegen and inline asm.
- Adopt for new codegen first. Convert existing raw emit sites only when already
  touching the surrounding code or when a bug fix proves the helper useful.

## Non-goals

- No flag-day conversion of all existing byte emission.
- No constant-per-instruction scheme. Register fields, displacements, immediates,
  and addressing modes make constants the wrong abstraction for most forms.
- No full text assembler in this ticket. A text parser for inline asm can sit on
  top of the encoder core later, but the encoder is the shared lower layer.

## Acceptance

- New ARM codegen work can express common instruction forms through typed
  encoder helpers instead of raw bitfield composition at the call site.
- Encoding tests cover the helpers added in the first pass, including at least
  one branch displacement form and one load/store displacement form per ARM
  backend.
- Existing fixedpoint/bootstrap checks remain byte-identical for any converted
  call sites.
- Inline raw bytes/words remain centralized and commented inside encoder bodies
  so the encoding remains auditable.

## Notes

- Treat this as a forward-adoption feature, not a refactor project. The value is
  in making upcoming codegen safer and clearer.
- Good trigger point: start this before or during `feature-cross-exceptions`, so
  the new ARM exception emission does not add another layer of hand-packed
  instruction words.
