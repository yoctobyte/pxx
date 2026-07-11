---
prio: 35
---

# `otherwise` as case-else soft keyword (FPC default-mode parity)

- **Type:** feature (Pascal frontend, small) — Track P
- **Status:** done
  conformance burn-down in [[bug-case-of-string-segfault-and-label-validation]]
- **Owner:** opus-fruit

## What

`otherwise` (ISO 10206 origin) as a synonym of `else` inside `case`:

```pascal
case i of
  1: n := 1;
  otherwise n := 99;   { = else n := 99; }
end;
```

**Verified 2026-07-11: stock FPC 3.2.2 accepts this in its DEFAULT mode** —
no `{$mode ExtendedPascal}` needed. So under the FPC-compatible bar this is
a real (tiny) gap, not an ISO curiosity. Like `else`, it takes an implicit
statement list up to `end`.

## Where

`ParseCaseStatementAST` (parser.inc): treat ident `otherwise` at
branch-start exactly like `tkElse` — soft keyword (only special in that
position; pxx has soft-keyword precedent, v136-9). No AST/IR change: reuse
the existing else-branch node shape.

## Payoff

Burns conformance skip `tcase50.pp` (currently misfiled as "ExtendedPascal
`otherwise` clause"; fix the reason or delete the entry when this lands).
Add a positive test (otherwise-branch taken/not-taken) and keep a variable
named `otherwise` compiling outside case (soft-keyword regression).

## Gate

`make test` + self-host fixedpoint (shared parser.inc = A-gated);
`tools/run_pascal_conformance.sh --only 'tcase*'`.

## Log
- 2026-07-11 — resolved, commit 5a27ba18.
