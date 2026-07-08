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
