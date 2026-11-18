---
track: C
tags: [cfront, k-and-r, old-style, pathb, tinyx]
prio: 80
type: feature
blocked-by: []
summary: "K&R (old-style) function definitions, `int f(a, b) char *a; int b; BODY`, were refused as \"stray token at top level\". About 40 TinyX server files (mi/, dix/, Xext/) use them. They are now rewritten into prototype definitions before pass 1, and an undeclared parameter is int."
status: done
owner: pxx2
---

# K&R function definitions

cparser.inc CRewriteKnRDefs runs once over the user's tokens before pass 1
(ParseCProgram). At file scope, `NAME ( id, id, ... )` followed by
declarations and then the body's opening brace becomes `NAME (decl, decl, ...)`:

- Each declaration's specifiers are copied in front of each of its
  declarators.
- A parameter with no declaration gets C89's implicit `int`.

The rewrite only fires on that exact shape: every declarator must name a
listed parameter once, and there must be no braces and no `=` among the
declarations. Prototypes, attributes and asm labels are left alone.

**Known difference:** a K&R `float` parameter is promoted to double at the
call when no prototype is in scope. After the rewrite it is a prototyped
float. The two agree whenever a prototype is visible, which is the case for
X's headers.

**Not covered:** `int f(x) BODY` with no declarations at all. It is ambiguous
with a prototype whose parameter type is a typedef, unless typedef knowledge
is used.

Test: test/c_knr_definitions.c (row c_knrdef26, gcc -std=gnu89) on x86-64 and
i386. It covers implicit int, a function-pointer parameter, an array
parameter, `register`, `const` and a typedef pointer. With this change, TinyX
went from 119/177 files compiling to all Xfbdev files compiling.
