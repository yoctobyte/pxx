# C `sizeof expr` without parentheses fails to parse

- **Type:** bug (cparser), likely EASY. Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00038: `if (sizeof 0 < 2)` — "Expected: ), but got: (Kind: 2, Line: 8)".
  `sizeof unary-expression` is valid C; parens only required for type names.
  Same test also uses `sizeof p` (ident) and `sizeof(&x)`.

## Fix site
cparser.inc sizeof parsing: if next token isn't `(`, or `(` is followed by an
expression not a type name, parse unary-expression.

## Gate
Drop 00038.c from test/c-conformance/pxx.skip; runner green.
