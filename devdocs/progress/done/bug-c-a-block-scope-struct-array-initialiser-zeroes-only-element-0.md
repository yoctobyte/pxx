---
track: C
tags: [cfront, arrays, initialisers, zero-fill]
prio: 75
type: bug
blocked-by: []
summary: "`struct S a[4] = { {1} };` in a block zeroed only a[0] before the element stores, so a[1..3] (and every element a partial row leaves out, 1-D or multidim) kept stack garbage; C99 6.7.8p21 says zero. The zero-fill is `a := Default` and a C array of records is typed as its element, so IR_DEFAULT_MEM got RecSize. In the v452 pin too. Found while checking LVGL's palette tables."
status: done
owner: pxx2
---

# A block-scope struct array initialiser zeroed only element 0

ir.inc, the AN_DEFAULT store: an array ident of records (no managed fields)
zeroes ArrLen * RecSize, as the scalar-array arm beside it already did.

Test: test/c_block_struct_array_init.c (row c_bsainit26; a dirtied stack
frame first) against gcc, x86-64 and i386.
