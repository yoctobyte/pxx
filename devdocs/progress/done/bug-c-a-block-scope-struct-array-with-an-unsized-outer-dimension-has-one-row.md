---
track: C
tags: [cfront, arrays, initialisers, lvgl, pathb]
prio: 80
type: bug
blocked-by: []
summary: "In a block, `static const lv_color_t colors[][5] = { {..}, {..}, .. }` (an array of STRUCTS with an unsized outer dimension, 2-D or more) kept the outer dimension at the 1 it was clamped to: sizeof 9 where gcc says 18, and every row past the first read zero. LVGL's lv_palette_lighten/darken returned black, so the default theme painted the screen and all text black. File scope and scalar elements were right."
status: done
owner: pxx2
---

# A block-scope struct array with an unsized outer dimension

cparser.inc, the block-scope array declaration: the scalar multidim walk
re-sizes an unsized outer dimension from the braces, the record path did not.
Now a record array takes its rows from the initialiser: one per top-level
brace group (gcc: a top-level brace is a row whatever it holds), or, for a flat
list, the records consumed under brace elision (CInitCountRecordArrayAt)
divided by the inner span.

Test: test/c_block_struct_array_init.c (row c_bsainit26) against gcc, x86-64
and i386.
