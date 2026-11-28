---
slug: feature-c-generic-on-a-cast-or-conditional-pointer
track: C
prio: 65
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1: first error of 297 libsystemd/libudev units)
tags: [cfront, generic, systemd]
summary: "_Generic described a pointer only when the controlling expression was a variable. A cast to a pointer type, a ?: of two pointers and &x all arrived as a bare pointer with no pointee and matched no pointer association, and a T ** variable was mis-described too (its inner level was built from PtrElemTk, itself a pointer). systemd's const_generic() is _Generic(0 ? (ptr) : (void *) 1, const void *: ..., void *: ...). Now CExprCG describes casts (pointee constness captured at the cast, CCastPointeeConst), ?: per C11 6.5.15p6 (null pointer constant arm, void * arm, qualifiers of both arms merged), &x, and pointers of any depth via CGPtrChain. Test c_gencc26: 26 selections against gcc."
---

# _Generic on a cast or a conditional of pointers
