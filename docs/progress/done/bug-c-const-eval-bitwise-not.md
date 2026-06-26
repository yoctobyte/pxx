# C const-eval: `~` (bitwise NOT) yields wrong value

- **Type:** bug
- **Track:** D (C frontend) — root fixed by Track A
- **Opened:** 2026-06-25
- **Found-by:** Slice A (lexer operator fidelity) fixture work.

## Symptom

In a C enum/macro constant expression, unary `~` evaluates wrong:

```c
enum { N0 = ~0, N5 = ~5, NM = ~0 & 255 };
```

gcc: `N0=-1`, `N5=-6`, `NM=255`. pascal26 (both pinned and HEAD): `N0=1`,
`N5=4`, `NM=1`.

## Root cause (suspected)

`CEvalConstPrimary` (cparser.inc) lowers `~` as
`Result := not CEvalConstPrimary()`. The self-hosted compiler types
`not <function-call result>` as **boolean**, not bitwise Int64 — the residual of
the `not Int64 expr typed boolean` family (see
project_not_int64_expr_done: the fix trusted ordinal-casts and pure arith
binops, but a bare `AN_CALL` result is not covered). So `not 0` → `1` (TRUE)
instead of `-1`.

Pre-existing (pinned reproduces it) — **not** a Slice A regression. Slice A
only added distinct multi-char operator tokens; `~` was already `tkNot`.

## Fix options

- Make `CEvalConstPrimary`'s `~` path explicitly bitwise: bind the operand to a
  Int64 temp and XOR with `-1` (`Result := CEvalConstPrimary() xor (-1)`), side-
  stepping the `not`-typing quirk. Cheap, local to the C const-evaluator.
- Or fix the underlying `not <AN_CALL Int64-result>` typing in the Pascal
  front-end (broader; touches the bug-esp-not-always-boolean family).

Prefer the local XOR rewrite for the C path; leave the general `not`-typing bug
to Track A.

## Test

Add a `~`-bearing enum to `test/cslicea_lib.c` (`S_NOT = (~0) & 0xFF` → 255)
once fixed; today it is omitted from the Slice A fixture to keep it green.

## Resolution (2026-06-26, Track A — commit on master, pin v79)
Root fixed at source: the Pascal front-end now types `not <ordinal-returning
call>` as bitwise (parser.inc tkNot trusts an AN_CALL whose proc RetType is a
non-boolean ordinal; a Boolean RetType stays logical). The compiler's own
`Result := not CEvalConstPrimary()` (Int64 return) therefore folds `~0` to -1,
`~5` to -6, `~0 & 255` to 255 — no cparser.inc XOR workaround needed. Verified
on Pascal (`not Int64Fn` = -1, boolean fn stays logical); self-host
byte-identical; make test green. Track C: rebuild feat/cfront on pin v79 and the
`~`-bearing enum fixture should match gcc; this ticket can be confirmed-closed
there.
