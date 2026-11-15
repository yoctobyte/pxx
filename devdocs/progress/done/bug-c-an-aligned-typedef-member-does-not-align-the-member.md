---
slug: bug-c-an-aligned-typedef-member-does-not-align-the-member
track: C
prio: 55
type: bug
status: done
created: 2026-11-15
found-by: measured while fixing attribute mode (2026-11-15), present on ~/pxx-frozen/latest too
tags: [cfront, layout, silent]
blocked-by: []
summary: "`typedef int al_t __attribute__((aligned(16))); struct sa { char c; al_t x; };` was 8 bytes under pxx, 32 under gcc: a scalar typedef's aligned(N) was dropped. It is now recorded per typedef (CTypedefAlign, from any aligned attribute in the typedef declaration or inherited through `typedef al_t al2_t`), carried by ParseCDeclType as CTypeTypedefAlign, and applied as the member TYPE's alignment (so packed and #pragma pack still cap it, as gcc does), by _Alignof(type), and by global placement (CDeclAttrAlign). A pointer to it (`al_t *p`, `typedef al_t *alp`) stays pointer-aligned. Aligned typedefs that were aggregates already worked. Test: c_tdal (test/c_typedef_aligned.c, expected = gcc's output). LOCALS are not done: no over-aligned local is honoured, typedef or attribute (feature-c-an-over-aligned-local-is-not-aligned)."
---
