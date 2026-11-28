---
title: "x86-64 inline asm: movntdqa, movaps, movups"
status: done
owner: claude-dupwt
prio: 60
area: asm
---

drm's __memcpy_ntdqa (drm_cache.c, and i915_memcpy.c the same) reads
write-combined memory with SSE4.1's non-temporal load `movntdqa` and stores
with `movaps`. pxx's in-house assembler encoded neither, so the routine was
poisoned: "its inline asm uses movntdqa, which the x86-64 assembler in pxx
does not encode". Found in the GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

- movntdqa xmm, m128 is 66 [REX] 0F 38 2A /r, a three-byte opcode, so it gets
  its own emitter arm. It is a load only, with a memory operand.
- movaps (0F 28 load, 0F 29 store) and movups (0F 10, 0F 11) are the
  no-prefix packed-single moves, added to the SSE move tables.
- The AT&T reader takes all three as whole words.

The encodings were checked against GNU as, including xmm9 and an r8 base.
Test row c_movnt26 runs drm's copy loop against gcc.
