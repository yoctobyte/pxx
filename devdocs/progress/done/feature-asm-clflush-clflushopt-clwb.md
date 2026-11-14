---
slug: feature-asm-clflush-clflushopt-clwb
track: C
prio: 40
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [asm, toybox]
blocked-by: []
summary: "The in-house assembler encodes clflush (0F AE /7), clflushopt (66 0F AE /7) and clwb (66 0F AE /6), memory operand only; AT&T inline asm accepts them. Needed by Gibux vtd.c."
---

# asm: cache-line flush instructions

asmenc.inc + the asmatt.inc allowlist. clwb is assembled in the test but not
executed (plexus's CPU lacks it).
