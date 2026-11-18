---
track: C
tags: [c, int128, attributes]
prio: 40
type: feature
blocked-by: []
summary: "__int128 works on x86-64 only. Still missing: other targets, int128<->float conversion, 16-byte alignment of a stack-passed __int128, and the narrow mode(QI/HI/SI) re-sizing (still skipped)."
status: open
owner: unassigned
---

# __int128 beyond x86-64, and the narrow attribute modes

Follow-up to [[feature-c-int128-and-attribute-mode]] (x86-64, 2026-11-18).

- **Other targets.** Each one refuses `__int128` by name. aarch64 is the
  natural next target: x0:x1 pairs, with `umulh` for the high half of a product.
  i386 and the 32-bit targets would need four-word values.
- **Float conversion.** Both directions are refused. This needs a correctly
  rounded conversion in pxx's own RTL (no libgcc). No corpus program has hit
  it yet.
- **Stack-passed alignment.** SysV aligns an `__int128` passed in memory to 16
  bytes. pxx passes it as two adjacent 8-byte slots without padding, which is
  only wrong when a call has run out of registers AND the callee was compiled
  by gcc.
- **mode(QI/HI/SI/DI).** Still skipped, so the typedef keeps its base type;
  `int x __attribute__((mode(QI)))` stays 4 bytes. No corpus program has hit
  it yet.
