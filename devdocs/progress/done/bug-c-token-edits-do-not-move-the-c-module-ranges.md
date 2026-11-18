---
track: C
tags: [cfront, linkage, static, modules, pathb, freetype]
prio: 80
type: bug
blocked-by: []
summary: "AdjustSrcRanges moved the Pascal and DWARF range tables on a token insert/remove but not the C module table (CModRangeStart). Split typedefs in an included .c pushed its last tokens past the module end, into the main source's range, so a `static` body there became a second row apart from its prototype and an --emit-obj object kept the name undefined. freetype's unity type1.c lost T1_Get_Track_Kerning, so Xft could not link."
status: done
owner: pxx2
---

# Token edits did not move the C module ranges

dbg_filetable.inc AdjustSrcRanges shifts CModRangeStart too.

Test: test/c_module_range_shift.c + c_module_range_shift_mod.c (row
c_modrs26) against gcc, x86-64 and i386, plus an --emit-obj object with
last_fn defined.
