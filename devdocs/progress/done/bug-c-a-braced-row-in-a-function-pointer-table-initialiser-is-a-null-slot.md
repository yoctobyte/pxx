---
slug: bug-c-a-braced-row-in-a-function-pointer-table-initialiser-is-a-null-slot
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-20
closed: 2026-11-20
found-by: pxx2, every Athena app stopped with "Runtime error 216 (nil reference)" in XPutImage
tags: [cfront, initializer]
summary: "A global table of function pointers with two or more dims, initialised in braced rows (`{ {fa, fb}, {fb, fa} }`), stored nothing: ParseCGlobalVarDecl's fn-pointer element loop took each inner brace as one element and skipped it as a null slot. Rows now nest (span = product of the inner dims), designators inside a row count from the row, and an unbounded first dim holds whole rows. A flat initialiser and 1-dim tables were already right. test/c_fnptr_table_braced_rows.c (c_fptab26)."
---

# A braced row in a function-pointer table initialiser was a null slot

libX11 PutImage.c: `static void (* RConst (SwapFunction[12][12]))(...) = { {NoSwap, ...}, ... };`.
Every slot was 0, so SendXYImage's `(*swapfunc)(...)` hit pxx's nil check.
XCreateBitmapFromData runs it, and so does every Xt app at start-up (xeyes'
icon). It was found by catching exit_group in gdb and symbolising the stack by
hand, because no frame pointers survive the shared runtime. Present at HEAD
before this change. The Xt crash fixed in
bug-c-an-array-typedef-of-pointers-is-read-as-a-pointer-to-the-array had hidden it.

Local tables (function scope) take a different path and were not checked here.
