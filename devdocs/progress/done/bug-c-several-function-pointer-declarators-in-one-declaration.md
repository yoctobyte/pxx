---
slug: bug-c-several-function-pointer-declarators-in-one-declaration
track: C
prio: 55
type: bug
status: done
created: 2026-11-16
found-by: pxx (Gibux seat), rump-pxx g08 (NetBSD sys/dtrace_bsd.h)
tags: [cfront, declarators]
blocked-by: []
summary: "`extern pf_t a, b;` (pf_t a function-pointer typedef) and `extern void (*c)(int), (*d)(int);` stopped at the second declarator (stray token). The top-level passes now run CSplitDeclarators(False) first, which splits a plain declaration the same way a typedef is split, but only for those two shapes, and never across a depth-0 brace (function body, braced initialiser); an initialiser stays with its declarator. Test: c_dcls."
---
