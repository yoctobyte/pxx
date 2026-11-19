---
slug: bug-c-asm-in-an-unused-static-inline-function-stops-the-compile
track: C
prio: 50
type: bug
status: done
created: 2026-11-16
found-by: pxx (Nilix seat), rump-pxx g20 (x86 invpcid) and the same shape on --target=xtensa
tags: [cfront, inline-asm]
blocked-by: []
summary: "A `static inline` function that is never called still has its inline asm assembled, so an instruction pxx's assembler lacks (invpcid) or any x86 asm on Xtensa (\"inasm with a non-empty template is only supported on x86-64, i386 and aarch64\") stops the compile. gcc never emits an unused static inline. Defer asm assembly to emission, or skip unused static inline bodies."
---

## 2026-11-17: the xtensa half is done

feature-c-xtensa-inline-asm-templates: xtensa encodes C templates at codegen
and asks `AsmXtensaLineKnown` at parse time, so an unknown instruction in an
unused static inline poisons the routine instead of stopping the compile. The
x86 half (invpcid in rump-pxx g20) is still open: x86 encodes at parse time.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).

## 2026-11-19: the x86 half is done

- x86-64 and i386 now do what xtensa does. In a `static` routine or one
  from an imported header, an instruction the encoder lacks is recorded
  (asmatt.inc AttUnsupported: AttPoisonable/AttUnknown, skipping the rest of
  that instruction), the block's bytes or i386 lines are dropped, and the
  routine is poisoned (cparser.inc CAsmMayPoison/CAsmX86Poisoned). A call
  refuses with `cannot call X: its inline asm uses "...", which the x86-64
  assembler in pxx does not encode`. Anywhere else the compile still stops
  at the instruction.
- ir.inc: a C `static` caller of a poisoned routine inherits the poison
  rather than refusing (before, only imported-header callers did), so a
  static inline chain nobody calls compiles, as with gcc.
- g20 itself had already been passing: invpcid is encoded now.
- Test: tools/check_casm_unknown_poison.py (test-core), with
  test/casm_unknown_insn_poison.c, on x86-64 and i386. It has a positive
  control for both refusals. The latest compiler fails it.
- Not part of this ticket: `bswap` with an "+r" operand is refused on
  i386 (on x86-64 it works). Filed separately.

Nilix is named Rainyday since 2026-11-18.
