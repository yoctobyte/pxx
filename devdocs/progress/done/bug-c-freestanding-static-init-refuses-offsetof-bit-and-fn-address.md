---
track: C
tags: [cfront, freestanding, emit-obj, static-init, rump, netbsd]
prio: 55
type: bug
blocked-by: []
summary: "Under --freestanding a file-scope initialiser must fold into .data, and the folder (ir.inc CBakeIntValue/CBakeAddrValue) refused three kernel staples: __builtin_offsetof (`&((T *)0)->f`, every vop_*_desc), NetBSD's __BIT(n) (a constant ternary over a comparison: every filterops' f_flags), and `__typeof__(fn) *p = &f` (__strict_weak_alias). rump-pxx g28, g29, g30; row 4 of the 6ee4a858b8 re-measure (21 files first-blocked)."
status: done
owner: pxx2
---

# Freestanding static initialisers: offsetof, __BIT, &function

ir.inc:
- CBakeConstAddr: an address that is a number -- a dereferenced integer
  constant plus fields and constant subscripts of array members; CBakeIntValue
  takes AN_ADDR through it.
- CBakeIntValue: AN_TERNARY with a constant condition (only the chosen arm must
  fold) and the six comparisons, unsigned where TypeCompareUnsigned says so.
- CBakeAddrValue: `&` of a function is the function.
- The refusal now prints the expression's shape three levels deep
  (`5:31(67(..) 67(..))`), so the next unfoldable construct names itself.

Test: test/c_static_init_fold_data.c as a freestanding x86-64 object, linked
with c_static_init_fold_main.c, against gcc's object. xtensa folds the same
values as gcc -m32. i386 --freestanding objects still bake no .data at all
(CPlaceGlobalInData is x86-64/ESP only) -- unchanged.
