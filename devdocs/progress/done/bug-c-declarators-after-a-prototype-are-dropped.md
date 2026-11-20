---
slug: bug-c-declarators-after-a-prototype-are-dropped
track: C
prio: 50
type: bug
status: done
owner: pxx2
created: 2026-11-20
closed: 2026-11-20
found-by: pxx2, building xedit for the Path B JWM desktop
tags: [cfront]
summary: "`T f(int), g(int), x;` at file scope declared f and nothing after it. ParseCSubroutine took the prototype and skipped to the `;`. CSplitDeclarators now splits a declaration whose first declarator is a prototype, as it already did for function-pointer declarators. test/c_decls_after_prototype.c (c_declproto26)."
---

# Declarators after a prototype were dropped

xedit.h declares `FileAccess MaybeCreateFile(const char*), CheckFilePermissions(const char*, Boolean*);`.
Before the fix, every use of the second name failed with "call to undeclared
function". A variable followed by a prototype (`int x, f(int);`) already
worked. The fix is the first condition in CSplitDeclarators's `not isTypedef`
block (cparser.inc).
