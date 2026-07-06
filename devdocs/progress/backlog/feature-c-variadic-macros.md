# C preprocessor: __VA_ARGS__ variadic macros

- **Type:** feature (cpreproc). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00083: `#define CALL(FUN, ...) FUN(__VA_ARGS__)` — exit 2
- 00084: `#define ARGS(...) __VA_ARGS__` — exit 2

Exit 2 not compile error → macro expands to SOMETHING but drops/garbles the
variadic tail (second check in each test fails).

## Fix site
compiler/cpreproc.inc macro parameter collection + expansion: `...` parameter,
`__VA_ARGS__` substitution (comma-joined rest args, empty allowed).

## Gate
Drop 00083.c/00084.c from test/c-conformance/pxx.skip; runner green.
