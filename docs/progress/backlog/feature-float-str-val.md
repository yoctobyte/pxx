# Float Str / Val

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §4)

## Motivation

`Str`/`Val` are implemented for integers only (`lib/rtl/builtin.pas`). Float
conversion is the remaining gap. (Float intrinsics `Trunc`/`Round`/`Int` are
already done — `test/test_float_intrinsics.pas`.)

## Scope

- Float `Val`: reuse the native float parser `StrToDoubleBits` (lexer.inc).
- Float `Str`: reuse the `writeln` float formatter.
- Wiring is nearly free per todo.md: `Val` is a plain proc → add a `Double`
  overload, resolver picks by destination type. `Str` is parser-intercepted →
  desugar dispatches on the value's `ASTTk` (float → `StrFloat`, else `StrInt`).
- `:w:d` widths stay literals (matches `write`); expression widths out of scope
  (see `feature-flexcolumn-directive`).

If importing instead of rolling: `strtod` (`stdlib.h`, clean) — not `math.h`.
Don't block on the C-header arc.

## Acceptance

`Str`/`Val` round-trip `Double` values in a regression test; integer behavior
unchanged.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
