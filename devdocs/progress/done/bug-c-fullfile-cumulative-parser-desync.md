---
prio: 40
---

# C: cumulative parser desync ("stray token at top level") on large multi-function files

- **Type:** bug. Track C (C frontend).
- **Found:** 2026-07-09, isolating c-testsuite 00216.

## Symptom
Compiling the near-complete set of 00216's top-level functions together fails in
PASS 1 (header/layout pass) with:
```
error: stray token at top level (not a declaration): ''
```
The offending token has an EMPTY SVal and is detected at EOF — i.e. the parser is
off by one closing brace / one token by the end of the file. Reproduces on the
PINNED v185 binary, so it PREDATES and is unrelated to the compound-literal work.

## Isolation (all with 00216's globals + guv2 patched to positional)
- Each function group compiles fine ALONE: `test_compound_with_relocs` (local
  array-of-record CL), `table[3]`+`test_multi_relocs`, `SEA/SEB/SEC/SED`+
  `test_zero_init`, `foo`.
- Every PAIR / TRIPLE tried also compiles.
- The FULL set (tcwr + sys_* + table + multi + SE + correct_filling + zero_init)
  desyncs by one.
Not a fixed-array cap: 00216 defines only ~15 types; MAX_UCLASS=2048,
MAX_UFIELD=262144, MAX_SYMS=131072, MAX_AST=524288 are far above use.

## Suspicion
An accumulation bug in the two-pass driver's token accounting or in some per-decl
state that is not fully reset between top-level declarations, tipping over only once
enough constructs precede. Needs bisection with brace-depth / TokPos instrumentation
across the pass-1 loop (cparser.inc ~6560) to find which decl leaves the cursor one
token short.

## Gate
The full 00216 function set parses without a stray-token desync; contributes to
unskipping c-testsuite 00216 (with [[bug-c-anonymous-member-designated-init]]).
[[feature-c-compound-literals]]

## RESOLVED 2026-07-09 — was an unhandled form-feed whitespace char (not accumulation)
Root cause found by instrumenting clexer's "unknown punctuation" fallback: the
stray empty-SVal token is a **form-feed (0x0C)**. The C lexer's whitespace skip set
was `[' ', #9, #10, #13]` — missing #12 (form-feed) and #11 (vertical-tab), both C6.4
whitespace. A form-feed fell through the char `case` to `else CurTok.Kind := tkIdent`
(empty SVal) → surfaced as "stray token at top level: ''". 00216 has TWO form-feeds
(source lines 220, 253, page-breaks between its later functions) — hence the
"cumulative / only-with-all-functions" illusion (subsets excluding those lines never
hit the char). NOT a cap, NOT #0, NOT unreset state. One-line fix in
`compiler/clexer.inc` (main whitespace case + the string-continuation skips). Regression
test `test/cformfeed_whitespace_b220.c` (form-feed between two functions → exit 42),
self-host byte-identical. 00216 now stops at its remaining anonymous-member blocker
([[bug-c-anonymous-member-designated-init]]) instead of desyncing.
