---
prio: 55  # auto
---

# C expression result-type model: `!` width, shift result type, hex-constant typing

- **Type:** bug (C type semantics). Track C (C→IR lowering type computation).
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00178: `sizeof(!a)` prints 8, must be 4 — `!` yields int, we type it as operand/64-bit.
- 00104: `x = ~x; if (x != 0xffffffff)` fails — int32 -1 vs `0xffffffff` (unsigned int
  per C constant-typing rules) must compare equal after usual arithmetic conversions;
  we compare as 64-bit (-1 vs 4294967295).
- 00200: ISO C99 6.5.7p3 — `X << T` result type = promoted LEFT operand (battery
  checks sign+size of shift results via `sizeof((M)+0)` trick). Exit 1.

## Root cause family
cfront types intermediate results too wide (64-bit) / ignores the C constant-type
ladder (decimal vs hex, int → unsigned int → long ...) and integer-promotion result
types for `!`, `~`, `<<`, comparisons.

## Gate
Drop 00104.c/00178.c/00200.c from test/c-conformance/pxx.skip; runner green.
Sweep note: same model feeds sizeof, so check sizeof-of-expression paths after fix.

## Update 2026-07-07
00178 (sizeof of a general non-ident expression) FIXED (commit 827cddfc). Remaining:
- 00104: `~x == 0xffffffff` — C types a hex constant that overflows int as *unsigned int*; usual arithmetic conversions then make the int/unsigned compare equal. pxx types 0xffffffff as int64 -> unequal. Needs the C integer-constant type ladder (dec vs hex, int->unsigned->long) + conversion rules.
- 00200: `X << T` result type = promoted LEFT operand (a macro battery probing sign/size via sizeof((M)+0)).
- Also: an ident-starting sizeof expr `sizeof(a<b)` still sizes by the first ident (char=1) not the int result; same integer-type-model work.

## Log
- 2026-07-08 — resolved, commit d513ca8f.
