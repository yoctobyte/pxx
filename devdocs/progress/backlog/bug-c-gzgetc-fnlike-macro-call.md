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
