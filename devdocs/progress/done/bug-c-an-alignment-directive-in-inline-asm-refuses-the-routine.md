---
slug: bug-c-an-alignment-directive-in-inline-asm-refuses-the-routine
track: C
prio: 50
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx zstd recipe: zstd_decompress_block.c)
tags: [cfront, inline-asm]
summary: "`__asm__(\".p2align 6\")` inside a routine, a loop-alignment hint zstd's decompress loops use under gcc on x86-64, poisoned the routine (\"its inline asm uses .p2align, which the x86-64 assembler in pxx does not encode\"), so zstd did not build. AttEncodeOne now reads .p2align, .balign and .align with plain-number operands and drops them: the block's final offset is not known while it is encoded, and padding changes only speed. The file-scope path still pads. Test c_asmalign26."
---

# An alignment directive in inline asm refuses the routine

zstd 1.5.6, lib/decompress/zstd_decompress_block.c:

```c
#if defined(__GNUC__) && defined(__x86_64__)
    __asm__(".p2align 6");
    ...
        __asm__(".p2align 5");
```

The routine was poisoned and its first caller refused, so the whole
library failed to build.

Inside a routine, pxx cannot honour the alignment: the block is encoded
before the routine's final position is known, and the routine moves again
under `--function-sections`. Dropping the directive is what pxx already
does with the routine's own start, which is aligned only to 4. A
non-numeric operand (`.p2align foo`) is still an error.
