---
prio: 55  # auto
---

# C: string literal as binop operand must decay to char* value (== compare SIGSEGVs)

- **Type:** bug (C→IR lowering). Track C — but touches shared ir.inc AN_BINOP
  lowering, so coordinate per lane rules if Track A is active.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00112 (5 lines): `return "abc" == (void *)0;` — exit 139. The literal hits
  the Pascal string content-compare path, which dereferences the NULL operand.

## Why
In C a string literal in a comparison/arith context is a POINTER value: its
address past the 8-byte Pascal length prefix (same +8 the store/call paths
already apply). The binop lowering lacks that decay.

## Prior art (reverted 2026-07-06 — landed without ticket/review, pulled back out)
Previous session drafted in ir.inc AN_BINOP lowering: under CProgramMode, if an
operand is AN_STR_LIT, wrap it as IR_BINOP(operand + const 8) typed tyPointer.
Worked for the suite; needs review (does it belong in cparser-side lowering
instead of shared ir.inc? does it double-apply on paths that already add +8?).

## Gate
Drop 00112.c from test/c-conformance/pxx.skip; runner green; self-host clean.

## Log
- 2026-07-07 — resolved, commit a1cfe29f.
