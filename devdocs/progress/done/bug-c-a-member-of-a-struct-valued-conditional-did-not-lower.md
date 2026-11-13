---
track: C
tags: [c, frontend, dropbear]
prio: 50
type: bug
blocked-by: []
summary: "`(c ? a : b).f` on struct arms stopped with IR_UNSUPPORTED (kind 67): a conditional's value goes through a scalar temp, and a struct does not fit one. The member is now taken inside each arm, `c ? a.f : b.f`, which is the same expression. dropbear's mlkem768.c (libcrux's Eurydice_range_iter_next(...).tag) hit it."
status: done
owner: claude
---

# A member of a struct-valued conditional

Found building dropbear 2026.94 ([[feature-c-dropbear-builds-with-pxx]]).
libcrux_mlkem768_sha3.h defines

    #define Eurydice_range_iter_next(iter_ptr, t, ret_t) \
      (((iter_ptr)->start == (iter_ptr)->end)            \
           ? (CLITERAL(ret_t){.tag = None})              \
           : (CLITERAL(ret_t){.tag = Some, .f0 = (iter_ptr)->start++}))

and the caller tests `...next(&iter, size_t, Option_b3).tag == None`.
`Opt o = c ? a : b;` already worked (the assignment path copies the struct);
only a member taken directly off the conditional failed.

Fix (compiler/cparser.inc, CFieldOfTernary): when the base of `.f` is an
AN_TERNARY of struct type, the result is a new conditional with the same
condition and `arm.f` in each arm, recursing into nested conditional arms.
Only the selected arm is evaluated, as before, so the `start++` in one arm
runs exactly when C says it does.

Test: test/c_struct_ternary_member.c (diffed against gcc). It covers the
libcrux loop (loop count and final `start` expose an extra or missing
increment), nested conditionals, and a chained member `.inner.v`.
