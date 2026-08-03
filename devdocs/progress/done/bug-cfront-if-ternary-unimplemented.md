---
summary: "`?:` had no precedence level in the #if evaluator: the parse abandoned at the `?`, so the CONDITION's value became the whole expression's — `#if (1 ? 3 : 1) == N` was true for every N and `#if (0 ? 1 : 3) == N` for none. Silent, because a wrong #if just takes the other branch"
type: bug
track: C
prio: 70
status: done
owner: claude-AC@opus5
---

# `#if` conditional operator `?:` was never implemented

- **Type:** bug (C preprocessor — SILENT wrong branch selection) — **Track C**
- **Found:** 2026-08-03 by `claude-AC@opus5`, immediately after making `#error`
  fire ([[bug-cfront-error-directive-silently-ignored]]). It had been sitting in
  the c-testsuite the whole time; the tests that check it (00075, 00145) were
  "passing" because the `#error` meant to catch it was itself a no-op.

## Measured

The precedence chain ran `CPEvalExpr -> CPExprOr -> ... -> CPExprAtom`. There
was no level for `?:` anywhere in it, so on reaching `?` the parse simply
stopped and returned what it had — the condition. The comparison that followed
then read whatever was left, giving a value that was not merely wrong but
*degenerate*:

| expression | pxx before | gcc |
| --- | --- | --- |
| `#if (0 ? 1 : 3) == N` | false for **every** N (0, 1, 3, 99 all tried) | true iff N==3 |
| `#if (1 ? 3 : 1) == N` | true for **every** N | true iff N==3 |

That signature — "equals nothing" / "equals everything" — is what identified it.

## Why it stayed invisible

A wrong `#if` produces no diagnostic. It takes the other branch and compiles
something else, so the failure surfaces (if ever) far away as a missing symbol
or a wrong constant. The c-testsuite's own guard against exactly this is
`#error`, which pxx dropped — so the two tests that target `?:` reported green
while asserting nothing. Fixing `#error` is what surfaced this.

## Fix

`CPExprCond`, a new level between `CPEvalExpr` and `CPExprOr`, right-associative
so `a ? b : c ? d : e` groups as `a ? b : (c ? d : e)`. `CPExprAtom`'s
parenthesised sub-expression calls it too, so `(0 ? 1 : 3)` parses.

Both arms are evaluated, which matches what `&&` and `||` in this evaluator
already do. C says the untaken arm is not evaluated, but an `#if` expression
cannot have side effects, and the one trap that matters — division by zero,
which is precisely what the c-testsuite guards untaken arms with (`-1 ? 3 :
(0/0)`) — is already benign here: `CPExprMul` yields 0 for a zero divisor rather
than faulting.

### Landmine hit while writing it

The recursive calls need explicit `()`. Inside a function's own body a bare
parameterless function name is the **result variable** (standard Pascal, and
what FPC does), so `t := CPExprCond` silently read the result-so-far instead of
recursing: it consumed no input, returned 0, and the only symptom was a bogus
`expected ':'` pointing at a colon that was plainly right there. Diagnosed by
printing the position and character rather than re-reading the code — a minimal
`forward`-declared recursive function repro worked fine and disproved the first
theory.

## Verified

- `test/cpreproc_cond_line.c` (**new**, gated): false/true conditions, nonzero
  truth, both untaken-arm `0/0` guards, all three arms of a nested ternary,
  ternary as an operand of `+`, and under unary `!`. Exit 42 under gcc and pxx.
- `make test-c-conformance` **219 pass, 0 fail**, 1 known skip — 00075 and 00145
  now pass *genuinely* rather than by ignoring their own assertions.
- Corpora unaffected: lua, cJSON, zlib, duktape, quickjs, sqlite parity.

## Log
- 2026-08-03 — found and fixed alongside the `#error` work.
