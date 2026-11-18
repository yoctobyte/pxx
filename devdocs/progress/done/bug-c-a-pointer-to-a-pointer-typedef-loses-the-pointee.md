---
track: C
tags: [cfront, typedef, pointers, pathb, st]
prio: 85
type: bug
blocked-by: []
summary: "`typedef Glyph *Line; Line *line;` was read as ONE level over a pointer element with no pointee: `line[y][x]` strode 8 and yielded a pointer (sizeof 8, not 16), so a Glyph passed by value was loaded through as an address. st crashed in draw() on its first frame. `typedef int *IP; IP *p` gave `p[0][0]` 8 bytes too. `Glyph **line` was right."
status: done
owner: pxx2
---

# Stars over a pointer typedef lost the typedef's pointee

cparser.inc ParseCDeclType, the pointer suffix: when the base is a pointer
typedef with a known pointee, the stars add to the typedef's level (depth + 1)
and the pointee becomes the base, as if the type had been spelled out. A
typedef of `T **` (pointer element, depth not recorded) and a function typedef
keep the old reading.

Test: test/c_ptr_to_ptr_typedef.c (row c_pptd26) against gcc, x86-64 and i386.
