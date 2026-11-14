---
slug: feature-c-i386-link-for-c-objects
track: C
prio: 60
type: feature
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "`--link` is x86-64/aarch64 only ('the i386 object writer is a different format'), so toybox compiles all 205 units for i386 but cannot link. Options: i386 --link, or an i386 entry stub (like tools/pxx_freestanding_start.s: TCB in gs, init/fini arrays, environ) plus host `ld -m elf_i386`. pixx-f2 wants an i386 toybox."
---

# i386 link for C objects

Blocks the i386 half of feature-c-toybox-builds-with-pxx.
