---
slug: feature-c-an-over-aligned-local-is-not-aligned
track: C
prio: 40
type: feature
status: backlog
created: 2026-11-15
found-by: measured while fixing bug-c-an-aligned-typedef-member-does-not-align-the-member
tags: [cfront, layout, silent, stack]
blocked-by: []
summary: "A local declared `int l __attribute__((aligned(32)))`, or with an aligned typedef (`al_t l;`, aligned 16), is placed at its plain type's alignment: `&l % 32` is nonzero under pxx, 0 under gcc. Globals and struct members honour both. Up to 16 needs only slot alignment within the 16-aligned frame; above 16 needs gcc-style frame realignment (and rbp addressing that survives it). Matters for SIMD/FXSAVE buffers and DMA descriptors on the stack."
---
