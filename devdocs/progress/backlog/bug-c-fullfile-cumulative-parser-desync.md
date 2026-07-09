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
