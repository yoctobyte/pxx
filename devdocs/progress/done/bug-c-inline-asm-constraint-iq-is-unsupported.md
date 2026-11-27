---
title: "C inline asm: the \"iq\" constraint (immediate or byte register) was refused"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

FreeBSD's x86 atomic.h writes atomic_set_char and the other byte-sized
atomics as `"iq" (v)`: an immediate or a byte register. cfront refused it, and
it was the first error in 302 of the GPU-driver compiles in the second census
(feature-nodisx-linux-gpu-drivers-built-by-pxx). Almost every LinuxKPI header
reaches it.

Fix (compiler/cparser.inc, CAsmParseOperandSection): "iq", "qi", "nq" and
"qn" read as "q", and the Q forms as "Q". The register is always an allowed
choice, the same reading as "qm" and "rm". Test row c_alshiq26.
