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

## Update 2026-07-06
00024 (`typedef struct {int x;int y;} s; s v;`) now PASSES — the old bogus
"line 100" error was from the since-reverted CPullCrtl hand-declared-prototype
append path. Dropped from pxx.skip (enforced). Remaining work = 00046 only:
C11 anonymous struct/union MEMBERS (an unnamed `union {...};` / `struct {...};`
inside a struct, whose fields are accessed directly as `v.b1`, `v.c`). That is a
record-layout change (promote an unnamed aggregate member's fields into the
parent's name scope at the member's offset) — Track A-adjacent, own effort.
