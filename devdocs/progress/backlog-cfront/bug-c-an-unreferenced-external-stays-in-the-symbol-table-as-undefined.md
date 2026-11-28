---
slug: bug-c-an-unreferenced-external-stays-in-the-symbol-table-as-undefined
track: C
prio: 45
type: bug
status: backlog
owner: unassigned
created: 2026-11-28
found-by: pxx2 (wayland 1.24.0 replay; pixx-cc asked for a ticket)
tags: [cfront, elf, object, link]
summary: "An x86-64 C object keeps an UND symbol for an external that only a dropped static inline called. wayland's wayland-util.h has `wl_fixed_from_double` calling round(). In all 11 replayed wayland objects nm shows `U round`, with no relocation against it and no body for the inline. gcc's object names neither. done/bug-c-objects-require-externals-only-dead-code-called fixed the RELOCATIONS; the symbol-table entry stayed. Harmless to GNU ld (an unreferenced UND resolves to nothing needed), but it makes nm/readelf audits misleading, and a strict linker, `pxx --link` included, may demand a definition. Drop UND symbols that no relocation uses."
---

# An unreferenced external stays in the symbol table as undefined

Measured on `connection.c.o` from the `--shared-runtime --threadsafe`
replay:

```
readelf -rW connection.c.o | grep -c ' round'   -> 0    (no relocation)
nm connection.c.o | grep wl_fixed_from_double   -> (nothing: the inline was dropped)
nm -u connection.c.o | grep -w round            -> U round
```

gcc's object of the same unit lists neither.

The earlier fix (done/bug-c-objects-require-externals-only-dead-code-called)
stopped relocating call slots that only dead code used. The external's
symbol is still written as UND. The fix is to emit an UND symbol only when a
relocation or a C initializer refers to it, in the same place that decides
the slots.

Not a link blocker for round and friends: crtl defines them, and `pxx --link`
resolves them from the runtime (done/bug-crtl-declares-round-trunc-log2-and-
others-it-does-not-define, which was a misread). Still to check: does
`pxx --link` refuse an unreferenced UND for a name crtl really lacks?
