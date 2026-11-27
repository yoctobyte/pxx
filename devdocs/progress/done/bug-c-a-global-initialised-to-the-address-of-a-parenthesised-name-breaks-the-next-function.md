---
title: "C: `T *p = &(name);` at file scope broke the next function's local declarations"
status: done
owner: claude-dupwt
prio: 75
area: cfront
---

The global-initializer fast path for `&(` (ParseCGlobalVarDecl) assumed a C99
compound literal, `&(struct S){ ... }`, and called ParseCDeclType on whatever
followed the paren. For `&(name)` with name a variable, the type parser read
`name` as a declarator and left its state behind. The next function's first
local declaration then parsed as top-level tokens: "stray token at top level
(not a declaration)". The function could be a long way off: pxx's own appended
helpers (`__pxx_builtin_clz32`, after the main file) were enough, which is why
the error named line 7 of a 5-line file.

FreeBSD's SYSINIT/DATA_WSET is exactly this
(`static void const *__set_... = &(sym);`), so every LinuxKPI file with
module_init, MALLOC_DEFINE or SX_SYSINIT failed: about 40 of the 2100
GPU-driver compiles, plus the `'x'` and `'n'` variants
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Minimal: `int bar; void *q = &(bar); int f(unsigned x) { int n = 0; return n; }`.

Fix: after `&(`, take the compound-literal branch only when a type follows
(IsCTypeTok). Otherwise rewind to the `&` and replay the whole expression at
main, as for every other initializer the fast paths can't fold
(CDeferScalarPtrInitSkip). Test row c_gaddrpar26
(test/c_global_init_address_of_a_parenthesised_name.c) covers both forms; its
expected output is gcc's.
