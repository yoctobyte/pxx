---
prio: 30
---
# C lexer: block comment possibly not terminated at the FIRST `*/`

- **Type:** bug (clexer). Track C (C frontend).
- **Found:** 2026-07-07 while writing test/caddr_float_field_b190.c.

## Symptom
A comment containing `void*/` mid-text — i.e. `/* ... void*/ more words */` —
was ACCEPTED by pxx (compiled the file, ran fine) while gcc correctly ends the
comment at the first `*/` and errors on the trailing garbage. Suggests the pxx
C block-comment scanner is greedy (scans to the LAST `*/`?) or otherwise
diverges from C's first-terminator rule.

## Repro
    /* comment with void*/ stray tokens here */
    int main(void) { return 42; }
pxx: compiles, exit 42. gcc: syntax errors. Expected: pxx errors too.

## Risk
Real-world C with `*/` inside a comment body is rare but the divergence can
silently swallow CODE between two comments. Check whether nested-comment
handling (Pascal-side `{$...}` nesting default) leaked into the C scanner.

## Gate
Repro errors under pxx; c-conformance + corpus stay green; bXXX test.

## 2026-07-08 (fable-c) — premise CORRECTED: the comment scanner is fine
Traced with `--dump-cpp`: the preprocessor (cpreproc.inc ~1425) AND the clexer
block-comment scanner (clexer.inc ~213) both correctly END the comment at the
FIRST `*/`. For the repro, the preprocessed output is exactly
`   stray tokens here */` followed by `int main...` — i.e. the comment ended at
`void*/` as C requires. So the comment handling is NOT greedy.

The real divergence is the **C parser silently skipping unknown TOP-LEVEL
tokens**: ParseCProgram's pass loops end with `else Next`, so `stray`, `tokens`,
`here`, `*`, `/` are each skipped one at a time with no error, and the file
compiles. gcc errors on the stray tokens; pxx tolerates them.

This is a deliberate leniency (tolerate unmodelled top-level constructs —
pragmas, attributes, macro leftovers). Making the top level strict risks
rejecting valid corpus, so it's a design decision, not a lexer patch — and
low value (real C rarely has `*/`-in-comment followed by stray tokens). Retitle
as a top-level-strictness question if pursued; the comment-scanner angle is
closed.

## RESOLVED 2026-07-08 (fable-abc, Track A/C) — top level made strict, gcc parity

Made ParseCProgram reject an unknown bare IDENTIFIER at top level instead of
silently skipping it. Details:
- Root cause was the `else Next` in ParseCProgram's pass-1 dispatch (the
  comment scanner is fine — see corrected premise above). Skipping was
  LOAD-BEARING for two reasons: (1) pxxcio/crtl unit pulls are merged into the
  same token stream via CLexAppend (user EOF stripped), so pass 1/2 walk into
  the appended Pascal-unit tokens and must skip them; (2) storage-class
  specifiers (extern/static/inline/...) are not modelled as type tokens and were
  tolerated by skipping.
- Fix (compiler/cparser.inc): capture `userTokEnd := TokCount - 1` at
  ParseCProgram entry (before any pull) — the boundary of the user's C region.
  In the else branch, error ONLY when the token is a bare `tkIdent` inside the
  user region AND not a recognized storage/function specifier
  (CIsTopLevelSkipIdent: extern, static, register, auto, inline, __inline,
  _Noreturn, _Thread_local, __thread, __extension__, restrict, _Static_assert,
  _Alignas, __attribute__, asm, ...). Appended-unit tokens (index >= userTokEnd),
  stray punctuation, and specifiers still skip — preserving prior leniency and
  the whole corpus.
- Surfaced ONE genuine pre-existing gap: c-testsuite 00120 (`struct { enum { X }
  x; } s;`) was passing BY ACCIDENT (the anon-struct-with-nested-anon-enum
  global declarator `s` was silently skipped, X=0 happened to be the expected
  return). It is valid C, so filed [[bug-c-anon-struct-nested-enum-global]] and
  added 00120 to pxx.skip.

Gates (all green): repro rejects with "stray token at top level"; new negative
test test/cstray_toplevel_reject_b193.c wired into test-core; test-c-conformance
203 pass / 0 fail / 17 skip; make test; self-host byte-identical; test-lua green.
NOTE (not my change): test/csqlite_suite.c currently SIGSEGVs at runtime on
master HEAD — verified pre-existing (the pre-change compiler produces a
byte-identical, equally-segfaulting binary), so this change is codegen-neutral
for sqlite. Flagged separately.

## Log
- 2026-07-08 — resolved, commit a1b3dcab.
