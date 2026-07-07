---
prio: 50
---
# C: zlib.h `gzgetc` function-like macro call fails to parse

- **Type:** bug (cfront — cpreproc/cparser, function-like macro). Track C.
- **Found:** 2026-07-06, zlib bring-up (2nd blocker after
  [[bug-c-typedef-name-as-uninitialized-local]], now fixed).
- **Blocks:** [[feature-c-corpus-zlib]].

## Symptom
`crtl + zlib.h + example.c` fails to parse:
`Expected: ), but got: (Kind: 74, Line: N) near: gzgetc >>> file`
(the `Kind: 74` is just the error-reporter's token number, not meaningful.)

example.c calls `gzgetc(file)`. zlib.h defines `gzgetc` as a function-like macro
that inlines the fast path and falls back to a parenthesized function-name call:

```c
#define gzgetc(g) \
    ((g)->x.have ? (--(g)->x.have, (g)->x.pos++, *((g)->x.next)++) : (gzgetc)(g))
```

Two candidate triggers to isolate (reduce to a minimal repro first):
1. a function-like macro whose body is a parenthesized **comma-expression**;
2. the `(gzgetc)(g)` **parenthesized-function-name call** in the fallback arm
   (calling through `(name)` where `name` is also the macro under expansion).

## Next
Reduce to a minimal repro vs gcc, decide preproc-vs-parser, fix, add a
regression test. Then zlib's runner should get past example.c parsing.

## Gate
`crtl + zlib.h + example.c` parses; `make test-zlib` advances.


## RESOLVED 2026-07-07 (Track A+C, sole-A)
Isolated: NOT the comma-expression macro body (that always worked). The parse
failure `Expected ), but got (` was the `(gzgetc)(g)` **parenthesized-function-
name call**. A bare function name in parens decays to AN_PROCADDR (its address);
CNodeProcSig had no AN_PROCADDR case, so the trailing `(args)` was never applied
as a call and the postfix layer choked. Fix (cparser.inc CNodeProcSig): an
AN_PROCADDR callee's own proc index IS its call signature → `(name)(args)` lowers
to an indirect call through the address. Self-referential blue-paint already
handled (macro name not re-expanded inside its own body).

Result: zlib's example.c now PARSES, COMPILES and LINKS the runner (was
parse-blocked). test-zlib advanced from parse-fail to a link-stage
`undefined symbol: gz_error` — a separate zlib-internal-symbol issue, filed under
[[feature-c-corpus-zlib]], NOT this macro bug. Regression b171 (parenthesized
name call + self-ref macro fallback). make test self-host byte-identical;
c-conformance 195/0.
