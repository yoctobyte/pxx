---
slug: bug-c-aarch64-returns-a-small-struct-through-x8-where-aapcs64-uses-x0-x1
track: C
prio: 45
type: bug
status: backlog
created: 2026-11-23
found-by: feature-c-int128-other-targets-float-and-narrow-modes (claude-pxx), comparing call sites with clang --target=aarch64-linux-gnu -O1 -S
tags: [cfront, aarch64, abi]
blocked-by: []
summary: "On aarch64 a C function returning a struct of 16 bytes or less returns it through a hidden destination in x8. AAPCS64 (and clang) return it in x0:x1 (an HFA in v0..v3) and use x8 only above 16 bytes. pxx calling pxx agrees with itself, but a pxx caller of a clang-built `struct P f(void)` (`struct P { long a, b; }`) reads garbage, and a clang caller of a pxx-built one gets nothing in x0:x1."
---

# aarch64 returns small structs through x8

Measured 2026-11-23. For
`struct P { long a, b; }; extern struct P ext(void); long use(void) { struct P w = ext(); return w.a + w.b; }`
clang emits `bl ext; add x0, x1, x0`. pxx emits `mov x8, x0` (the hidden
destination) before the call and reads the struct back from memory.
`struct W { __int128 v; }` does the same. The callee side mirrors it.

AAPCS64 (the result-return rules): a composite of 16 bytes or less is returned in x0/x1,
an HFA in v0..v3; larger ones are returned via x8. ABIRetViaHiddenDestProc
(abi.inc) is the predicate to look at; ABIA64RecordClass already
classifies the shapes.

Can't be linked and tested on plexus (no aarch64 linker); compare call
sites with clang's -S output, as feature-c-int128-other-targets-float-and-narrow-modes did.
