---
slug: bug-c-typeof-of-a-function-declares-a-variable
track: C
prio: 45
type: bug
status: backlog
created: 2026-11-26
found-by: pxx2 (while testing bug-c-the-alias-attribute-was-ignored)
tags: [cfront, declarations, typeof]
blocked-by: []
summary: "`extern __typeof(f) g;` where f is a FUNCTION declares g as a variable, not a function. A call `g(...)` then fails at link with `undefined reference to extern variable 'g'` (an executable), or would call through the bytes at g (an object). gcc declares a function of f's type. libbsd's and glibc's alias idioms use it (`extern __typeof(impl) name __attribute__((alias(...)))`); it works today only when a prototype of g came first, as in dhcpcd."
---

# `__typeof` of a function declares a variable

```c
static int impl(int n, ...) { return n; }
extern __typeof(impl) g __attribute__((alias("impl")));
int main(void) { return g(0); }
```

pxx: `undefined reference to extern variable 'g'`. gcc: g is a function
`int (int, ...)`.

Fix direction: CExpandFnTypedefDecl already rewrites a declaration through a
FUNCTION TYPEDEF into an ordinary prototype in pass 1. `__typeof(f)` /
`typeof(f)` naming a function is the same shape; it needs f's parameter
tokens (the prototype or definition seen earlier) and can reuse that rewrite.
