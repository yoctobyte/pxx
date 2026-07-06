---
prio: 55  # auto
---

# C anonymous struct/union members (C11) reject with "expected C expression"

- **Type:** bug/feature. Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00024 (12 lines!): `typedef struct { int x; int y; } s; s v;` global var of
  typedef'd ANON struct — error "pascal26:100: expected C expression". NOTE the
  bogus line number (100 in a 12-line file) — error position comes from appended
  synthetic token region? Investigate separately, may be its own bug in the new
  CPullCrtlForPrototypes append path or two-pass line tracking.
- 00046: C11 anonymous members: unnamed `union {...};` / `struct {...};` inside a
  struct, members accessed as if direct (`v.b1`, `v.c`).

## Gate
Drop 00024.c/00046.c from test/c-conformance/pxx.skip; runner green.
