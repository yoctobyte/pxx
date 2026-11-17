---
track: C
tags: [cfront, wrong-code, fn-pointer, typedef, x11, pathb]
prio: 60
type: bug
blocked-by: []
summary: "Calling through an incremented pointer into a table of function pointers, `(*p++)(args)`, called through the wrong value (garbage result); with the table pointer typedef'd (`typedef ft *ftl;`, Xlib's XcmsFuncListPtr), held in a struct field, or declared as a later sibling (`ft *a, *b;`), the call did not parse. Found in libX11 xcms/CvCols.c."
status: done
owner: pxx2
---

# Call through an incremented pointer to function pointer

Found replaying libX11 through pxx (Path B, 2026-11-17), xcms/CvCols.c:
`while (...) if ((*src_to_CIEXYZ++)(ccc, ...) == XcmsFailure) ...`.

Four gaps, all on the "which signature does this callee have" channel:
1. CNodeProcSig had no AN_INCDEC arm: `(*p++)(a)` got no signature.
2. A pointer-to-fn-pointer TYPEDEF dropped the pointee signature
   (new CTypedefPtrElemProcSig, restored into CTypePtrElemProcSig on use).
3. A struct field of that typedef recorded no element signature (declStars = 0).
4. Sibling declarators (`ft *a, *b;`, `ft *a, b;`) reset it to -1.

Test: test/c_call_incdec_fnptr.c against gcc.

Not fixed, seen on the way: `ft **d; (**d)(a)` segfaults at run time, as the
first declarator too, before and after this change (two loads; the arm keeps
one). Wants its own ticket if something real hits it.
