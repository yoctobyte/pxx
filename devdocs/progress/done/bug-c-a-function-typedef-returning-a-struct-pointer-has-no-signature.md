---
track: C
tags: [cfront, typedef, fnptr, rump, netbsd]
prio: 55
type: bug
blocked-by: []
summary: "`typedef struct e *(lk_t)(struct t *, ...)` (NetBSD if_llatbl.h, 26 network files) went to the struct-typedef arm, which read lk_t as a plain pointer to struct e and dropped the parameter list: `lk_t *lk; t->lk(..)` had no call signature, so inside any parentheses the call was \"expected ')'\". And a function-type typedef never recorded its result's record, so `f(i)->b` / `f(i).b` read offset 0 (pre-existing, silent). rump-pxx g27."
status: done
owner: pxx2
---

# A function typedef returning a struct pointer

- CTypedefAggFnPtrDeclarator also sends `struct T *NAME(` (and `(NAME)(`, which
  CUnparenTypedefName unwraps) to the scalar arm, which registers function types.
- The function-type arm sets ProcRetPtrElemTk/Rec and ProcRetRecId on the
  signature, as the `$cfnptr` registration does.

At statement level the call happened to parse (a re-parse found it), which is
why only `(t->lk(..))` and call arguments failed.

Test: test/c_fn_typedef_struct_ret.c against gcc, x86-64 and i386.
