---
slug: bug-c-a-cast-to-a-union-used-the-value-as-the-unions-address
track: C
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pxx (Gibux seat), rump-pxx S7
tags: [cfront, gnu-extensions, silent]
blocked-by: []
summary: "GNU `(union u)5` compiled and segfaulted: the record-cast path yields the operand unchanged (right for struct-to-struct, where the operand IS the aggregate), so the scalar 5 became the union's address. A record cast of a non-record operand now builds a zeroed temporary of the union, stores the operand into the member of its type (else of its kind: floating, pointer, integer; else the first) and yields it as a compound literal, so `.i`, by-value passing and assignment all work. Test: test/c_rump_silent.c (S7 line)."
---
