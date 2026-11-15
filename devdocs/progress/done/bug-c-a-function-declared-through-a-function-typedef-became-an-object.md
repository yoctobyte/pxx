---
slug: bug-c-a-function-declared-through-a-function-typedef-became-an-object
track: C
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pxx (Gibux seat), rump-pxx S11 (NetBSD sys/conf.h dev_type_open)
tags: [cfront, declarators, silent]
blocked-by: []
summary: "`typedef int d_open_t(int, int); d_open_t yopen;` declares a FUNCTION (C 6.7.6.3); pxx made yopen a 4-byte object, and a call jumped into data. ParseCTypedef now records the typedef's return-type and parameter-list token ranges (CTypedefFnRetTok..RParTok), and CExpandFnTypedefDecl rewrites `[specifiers] T a, b;` in pass 1 into `[specifiers] R a(args); [specifiers] R b(args);`, which the prototype path already handles. Plain shape only (a name followed by `,` or `;`), file scope. Test: test/c_rump_silent.c (S11 line: multi-name, extern, static, pointer return, address taken)."
---
