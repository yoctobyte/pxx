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
