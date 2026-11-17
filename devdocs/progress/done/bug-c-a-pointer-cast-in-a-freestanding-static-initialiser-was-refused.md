---
track: C
tags: [C, freestanding, static-data, rump-pxx]
prio: 40
type: bug
blocked-by: []
summary: "Under --freestanding (and --c-static-data), a file-scope initialiser with a pointer cast was refused with \"not a constant this compiler can place in .data (AST node kind 39)\". Affected shapes: NULL as ((void *)0) in every struct initialiser, link-set entries (const void *)&sym, and device addresses (T *)0x60000000. The C baker now looks through AN_PTR_CAST for both the integer and the address case, and bakes `arr + k` on a global array. rump-pxx g19."
status: done
owner: unassigned
---

# A pointer cast in a freestanding static initialiser was refused

Fixed together with feature-xtensa-freestanding-objects-carry-the-idf-application-runtime
(CBakeIntValue / CBakeAddrValue, ir.inc). The repro is
`~/gibux/docs/rump-pxx/repros/g19_pointer_cast_in_static_init_freestanding.c`.
The test is test/c_freestanding_static_data.c (uart, self, bp, ip, lh0).
