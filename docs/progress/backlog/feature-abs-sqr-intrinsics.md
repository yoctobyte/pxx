# `Abs` / `Sqr` System intrinsics missing

- **Type:** feature (language) — Track A
- **Status:** backlog
- **Opened:** 2026-06-23
- **Found by:** differential probe vs FPC (`Abs(-5)`, `Sqr(7)` -> "undefined").

## Problem

`Abs(x)` and `Sqr(x)` are System intrinsics (no `uses`) and are unimplemented.
(`Succ`/`Pred`/`Odd` were added the same session as pure single-use rewrites;
`Abs`/`Sqr` are deferred because a naive rewrite is incorrect.)

## Why not a trivial rewrite

- `Sqr(e)` = `e*e` uses `e` TWICE — a naive fold double-evaluates a
  side-effecting argument (`Sqr(f())`). Needs the argument bound to a temp.
- `Abs(e)` needs a conditional (`if e<0 then -e else e`), not a pure expression —
  needs a temp + branch or a runtime helper, and must cover both integer and
  float operands.

## Fix options

A runtime helper (`__pxxAbsInt`/`__pxxAbsFloat`, `__pxxSqr*`) in the builtin unit
(with the usual pre-scan pull on `abs(`/`sqr(`), mirroring the string Copy/Delete
intrinsics), or an expression-temp mechanism so the argument is evaluated once.
Gate: `make test` + FPC oracle (int + float, negative/zero/positive).
