---
slug: feature-c-toybox-binary-is-13-mb
track: C
prio: 30
type: feature
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "The pxx-linked toybox is ~13 MB against gcc's 475 KB. Not investigated (debug data? unpruned sections despite --function-sections? code size)."
---

# toybox size

Measure section sizes first.

## Measured 2026-11-14 (b3c5f711ea, --function-sections, pxx --link with GC)

The link GC works as designed (`PXXDBG=a.objgc` says ELFGC-OK, 12,652 of 239,914
sections kept). Input is 113.6 MB across the 205 objects, and 29.1 MB survives,
counting bss. The cause is the object model: every object is a self-contained
runtime. See decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit.

| | pxx | gcc |
|---|---|---|
| .text | 8.28 MB | 286 KB |
| .data | 4.06 MB | 52 KB + 53 KB rodata |
| .bss | 16.8 MB | 9 KB |

What each object keeps after GC (false.o, whose own code is 34 bytes):

- `.text.__pxx_init_thunk`, 11.4 KB: it initialises crtl's globals for this unit
  (stdout, optind, environ, tz, ...).
- About 14 KB of Pascal RTL helpers (PXXAlloc, string, interface and record
  release, TInterfacedObject). They are LOCAL symbols, so no other object's copy
  can stand in. The unit's own .data (a TInterfacedObject VMT) and its thunk
  reach them.
- `.data` 18.7 KB and `.bss` 81.7 KB, kept whole because they are not split per
  symbol: pxx_env_buf 16 KB, pxx_tz_buf 8 KB, gr_line, asctime_buf, ...

205 objects x (about 25.7 KB text + 18.7 KB data + 81.7 KB bss) accounts for
most of the excess. Toybox's own global code is 463 KB, about 1.6x gcc's whole
.text.

Levers, roughly in order of payoff:
1. Emit the per-object runtime (Pascal RTL helpers and crtl statics) as weak or
   COMDAT, or dedupe identical local sections by name and content at --link.
2. Run the crtl state init once (in the object that defines the state), not in
   every unit's thunk.
3. Data sections per symbol (the -fdata-sections equivalent), so unreferenced
   buffers drop.

The same cause explains dropbear's ~9 MB programs and busybox's 25 MB.
