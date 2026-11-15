---
slug: bug-c-an-aligned-typedef-member-does-not-align-the-member
track: C
prio: 55
type: bug
status: backlog
created: 2026-11-15
found-by: measured while fixing attribute mode (2026-11-15), present on ~/pxx-frozen/latest too
tags: [cfront, layout, silent]
blocked-by: []
summary: "`typedef int al_t __attribute__((aligned(16))); struct sa { char c; al_t x; };` is 8 bytes under pxx, 32 under gcc: the typedef's alignment does not reach a struct member declared with it. Silent layout difference against any gcc-built object sharing the struct."
---
