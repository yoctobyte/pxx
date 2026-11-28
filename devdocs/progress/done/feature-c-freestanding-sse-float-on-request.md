---
title: "C: --freestanding SSE float on request (-msse, -msse2, -mhard-float)"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

pxx's --freestanding refuses every SSE instruction, because a kernel must not
touch user FPU state. gcc's -ffreestanding does not mean that: float stays on
until -mno-sse or -mgeneral-regs-only. Two real cases need float in
freestanding code:
- Linux builds its FPU units (amdgpu's display core, dc/dml) with
  CC_FLAGS_FPU = -msse -msse2 and brackets the calls with
  kernel_fpu_begin/end.
- Rainyday runs the DRM drivers as processes (drivers/gpu), which own their
  FPU state.
These were 44 compiles in the GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

The options:
- -msse, -msse2 and -mhard-float re-enable SSE float under --freestanding.
- -mno-sse, -mno-sse2 and -msoft-float turn it off again; the last one wins,
  as with gcc.
- With them, the variadic prologue writes the XMM half of the va_list save,
  so a variadic double works.
- Combining them with -mgeneral-regs-only is refused, since the two
  contradict each other.
- They are x86-64 only. In hosted code they change nothing.

Plain --freestanding is unchanged: a kernel unit that does not ask for float
is still refused at the first SSE instruction.

Test row c_fssse: a pxx --freestanding -msse2 object linked to a gcc main,
with float, double and variadic-double values equal to gcc's for the same
source.
