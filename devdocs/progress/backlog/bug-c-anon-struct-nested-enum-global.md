---
prio: 30  # auto
---

# C: anonymous struct global var with a NESTED anonymous enum member drops the declarator

- **Type:** bug (cparser global-var / struct-type parse). Track C.
- **Found:** 2026-07-08, surfaced by the new top-level stray-token error
  (bug-c-comment-terminator-greedy). c-testsuite 00120.

## Symptom
    struct { enum { X } x; } s;
    int main(void){ return X; }
`s` (the variable declarator) is left unconsumed at top level →
`error: stray token at top level (not a declaration): 's'`.

## Isolation (2026-07-08)
- `struct { int x; } s;` — WORKS (plain anon-struct global var).
- `enum { X };` at top level — WORKS.
- `struct { enum { X } x; } s;` — FAILS: the NESTED anonymous enum inside the
  anonymous struct body derails the type parse (global-var path parses the
  struct type but bails before the `s` declarator), so `s;` falls through to the
  top-level dispatch as stray tokens.

## History
Before the top-level stray-token error existed, `s` and `;` were silently
skipped by ParseCProgram's `else Next`, and the nested enum `X` still resolved
to 0 (the expected return), so 00120 PASSED BY ACCIDENT. The stray-token error
(correctly, per gcc, for real garbage) now surfaces this as a hard failure — but
00120 is VALID C, so this is a genuine parse gap, not a stray-token false
positive. Skipped in test/c-conformance/pxx.skip pending this fix.

## Root cause (to confirm)
`ParseCGlobalVarDecl` (or the anon-struct type reader it calls) does not handle a
nested anonymous `enum { ... }` inside an anonymous struct body — likely
`CStructBodyIsSimple` / the field-type reader stops at the inner `enum`. Fix:
parse a nested anon enum as a member type (register its enumerators in the
enclosing scope, member type = int), then continue reading the struct body and
the trailing declarator normally.

## Gate
Drop 00120.c from test/c-conformance/pxx.skip; runner green; make test +
self-host byte-identical.
