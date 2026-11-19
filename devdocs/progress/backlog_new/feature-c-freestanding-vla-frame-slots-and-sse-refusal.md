---
track: C
tags: [C, freestanding, x86-64, kernel]
prio: 40
type: feature
blocked-by: []
summary: "Left over from the Rainyday (ex-Nilix/Gibux) kernel umbrella, item 7: under --freestanding, alloca/VLA are refused because they use the red zone (give them real frame slots so a kernel may use a VLA), and a float/double operation is still emitted as SSE instead of refused (gcc -mgeneral-regs-only refuses it)."
status: open
owner: unassigned
created: 2026-11-19
---

# --freestanding: VLA/alloca without the red zone, and refuse SSE

Split out of feature-gibux-kernel-builds-with-pxx (item 7) when that
umbrella was closed: its acceptance, `make TOOLCHAIN=pxx test` in the
Rainyday kernel, has passed since 2026-11-13.

Done there already: --freestanding emits no SSE in the variadic prologue
and refuses the two red-zone code paths (alloca/VLA, FPU mask) rather than
emitting them.

Open:
- alloca/VLA: frame slots instead of the red zone, so kernel code may use
  a VLA (an interrupt arrives on the same stack; gcc builds the kernel with
  -mno-red-zone).
- A float/double operation in --freestanding code is emitted as SSE. gcc
  with -mgeneral-regs-only refuses it, and in a kernel the user's SSE
  state lives in those registers. Refuse it (or add a flag that does).

Reference: ~/rainyday/kernel/Makefile (the gcc flags), the Rainyday kernel
(githome:rainyday, private).
