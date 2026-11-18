---
track: C
tags: [cfront, bitfields, incdec, lvgl, pathb]
prio: 80
type: bug
blocked-by: []
summary: "`p->c++` / `++p->c` / `c--` on a C bitfield that does not start at bit 0 loaded and stored the whole storage unit: the new value landed at bit 0, over the neighbouring fields, and the field itself never changed. LVGL's lv_obj_t.style_cnt:6 (bit 4) stayed 0 after `obj->style_cnt++`, so lv_obj_add_style's `for (j = style_cnt - 1; j > i; j--)` ran 4 billion times. In the v452 pin too. `+=` was right (rewritten to an assignment)."
status: done
owner: pxx2
---

# ++/-- on a bitfield above bit 0

AN_INCDEC lowers through IR_LOAD_MEM/IR_STORE_MEM of the field's address and
never reached the bitfield read/store that AN_ASSIGN uses. CMakeIncDec now
rewrites a bitfield operand as `x OP= y` already is: `lv = lv +- 1`; prefix
yields the assignment, postfix yields it minus the step masked to the field
width (sign-extended for a signed field) in the field's promoted type.

Test: test/c_bitfield_incdec.c (row c_bfincdec26) against gcc, x86-64 and
i386.
