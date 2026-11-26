---
slug: feature-c-builtin-ia32-pause
track: C
prio: 40
type: feature
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx curl + mbedTLS recipe)
tags: [cfront, builtins]
summary: "`__builtin_ia32_pause()` (x86 PAUSE, a spin-wait hint) was 'call to undeclared function'. Every gcc for x86 has it, and pxx defines __GNUC__ and __x86_64__, so code tests for exactly that and calls it: curl's easy_lock.h spinlock. It is a no-op, which keeps its meaning (no effect on memory or values). Test c_asmbar26."
---
# `__builtin_ia32_pause`

curl 8.23.0 `lib/easy_lock.h` defines HAVE_BUILTIN_IA32_PAUSE for
`defined(__GNUC__) && !defined(__clang__)` on x86 and calls it inside its
spinlock's wait loop. Three of curl's units (easy.c, version.c, hostip.c)
failed on it.

It is handled next to `__builtin_unreachable`, as a statement that emits
nothing. A real PAUSE would save a little power in a contended spin; nothing
depends on it.
