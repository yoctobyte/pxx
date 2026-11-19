---
track: C
tags: [C, freestanding, x86-64, kernel]
prio: 40
type: feature
blocked-by: []
summary: "Left over from the Rainyday (ex-Nilix/Gibux) kernel umbrella, item 7: under --freestanding, alloca/VLA are refused because they use the red zone (give them real frame slots so a kernel may use a VLA), and a float/double operation is still emitted as SSE instead of refused (gcc -mgeneral-regs-only refuses it)."
status: done
owner: pxx (Rainyday seat)
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

## Done 2026-11-19

- VLA/alloca: IR_ALLOCA parks rdx/r10/r11 in three frame slots reserved
  with the alloca base (32 bytes instead of 8, only in bodies with an
  alloca), not in the red zone. --freestanding no longer refuses alloca/VLA.
  Hosted code takes the same path: c_vla, c_alloca_in_call_argument and
  c_alloca_expression_stack pass.
- SSE: under --freestanding, EmitAsmX64 refuses any line naming an xmm
  register in code from the user's own sources ("float/double arithmetic is
  not supported -- it needs the SSE registers ..."). Every SSE instruction
  the x86-64 code generator emits passes through it as text. Exempt: the
  units the compiler appends (compiler/builtin/, dropped by DCE when
  unused) and inline asm. Loads and copies of a double need no SSE (a double
  travels in rax) and still compile. gcc -mgeneral-regs-only accepts a
  comparison or a conversion by calling libgcc's soft-float, which a kernel
  does not link; pxx refuses those at compile time.
- Test: tools/check_freestanding_vla_sse.py (test-core) with
  test/c_freestanding_vla.c. The VLA object linked with gcc prints what
  gcc's prints, and its functions touch nothing below rsp. Four float cases
  are refused and two non-arithmetic double cases compile. Latest fails it.
- Rainyday (5115b9b) built with this compiler: make test, test-sh, and
  units 60/60 with -smp 4.
- Seen, not changed: a --freestanding object still carries the builtin
  fenv stubs (stmxcsr/ldmxcsr at [rsp-4]) until a link drops them.
