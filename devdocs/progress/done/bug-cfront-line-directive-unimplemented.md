---
summary: "`#line` was not implemented and `__LINE__` evaluated as an undefined identifier (0) inside `#if`, so `#if __LINE__ == N` was false for every N. Both silent; found once #error started firing"
type: bug
track: C
prio: 65
status: done
owner: claude-AC@opus5
---

# `#line` unimplemented, and `__LINE__` reads as 0 inside `#if`

- **Type:** bug (C preprocessor — SILENT wrong branch / wrong diagnostics line)
  — **Track C**
- **Found:** 2026-08-03 by `claude-AC@opus5` while clearing the c-testsuite
  failures that [[bug-cfront-error-directive-silently-ignored]] exposed
  (00152). Two independent defects that happen to meet in that one test.

## Measured

**`#line`** was not a directive the preprocessor knew, so it fell off the end of
the dispatch chain and was discarded — the following line kept its physical
number, and so did every `__LINE__` and diagnostic after it.

**`__LINE__` inside `#if`** is the subtler one. `__LINE__` is synthesised during
macro *expansion* (`CPExpandRange`), and the `#if` evaluator does not go through
that path — it resolves identifiers with `CPFindMacro`, which has no entry for
it. An unknown identifier evaluates to 0, per the C rule, so:

```c
#if __LINE__ == 0
```
was **true** in pxx at any line; gcc says false everywhere. Consequently
`#if __LINE__ == N` was false for every real N.

Both are silent in the same way `?:` was: a wrong `#if` just takes the other
branch.

## Fix

- `CPLineDirective`: macro-expands its operand first (`#define line 1000` /
  `#line line` is legal C and is what 00152 actually tests), parses the leading
  integer, and stores `N-1` into `CPCurLine` — the read loop `Inc`s before
  handling a line, so the next line becomes N. The optional `"file"` operand
  renames `CPCurPath` for later diagnostics.
- `CPExprAtom`: `__LINE__` answered as `CPCurLine` before the macro lookup, so
  the `#if` evaluator sees the same value expansion would have produced.

## Verified

- `test/cpreproc_cond_line.c` (**new**, gated, shared with the `?:` ticket):
  `__LINE__` is nonzero inside `#if`; `#line 1000` renumbers the next line;
  `#line RENUM` expands its macro operand; renumbering keeps counting on later
  lines. Exit 42 under gcc and pxx.
- `make test-c-conformance` **219 pass, 0 fail**, 1 known skip — 00152 passes.
- Corpora unaffected: lua, cJSON, zlib, duktape, quickjs, sqlite parity.

Note: while writing the test I got its own expected line number off by one, and
**pxx and gcc reported the identical line and message** — a good independent
signal that the renumbering matches, not just that it is nonzero.

## Log
- 2026-08-03 — found and fixed alongside the `#error` work.
