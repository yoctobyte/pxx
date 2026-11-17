---
track: C
tags: [cfront, wrong-code, cast, typedef, x11, pathb]
prio: 70
type: bug
blocked-by: []
summary: "A cast through a pointer typedef (`typedef struct D *PD; ((PD)p)->w`) lost the pointee struct: every member read offset 0 (the first field), and `((PD)p)->fn(a)` made no call at all, yielding the first field. Xlib's XAllocID macro is exactly this shape; 20 libX11/libXext/libXrender files failed to parse and others would have miscompiled. The cast now publishes a one-level pointer typedef the way `(struct D *)` does."
status: done
owner: pxx2
---

# Cast through a pointer typedef lost the pointee

Found replaying the X11 client libraries through pxx (Path B, 2026-11-17).
`ParseCDeclType` returns a pointer typedef as tyPointer with the pointee in
CTypeElemTk/Rec and depth 0 (the stars were in the typedef). The cast only
registered its pointee alias for depth > 0, so the cast value had no record.

Fix: compiler/cparser.inc, the cast arm of ParseCUnary, treats such a typedef
as depth 1. One level only; `T **` typedefs record no depth and are
bug-c-pointer-to-pointer-struct-member-reads-offset-0.

Test: test/c_cast_ptr_typedef.c (fields, member calls, `(*...->fn)()`, a
nested struct, a store, scalar and fn-pointer typedef casts), against gcc.
Replay after the fix: libXext 16/16, libXrender 13/13, libX11 403/410.
