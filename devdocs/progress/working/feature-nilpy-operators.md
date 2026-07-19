---
track: N
prio: 55
type: feature
claimed: claude-n-uforth
---

# NilPy: bitwise operators + augmented assignment

Part of [[feature-nilpy-corpus-uforth]] milestone 1. uforth census: `+=` 83,
`&` 24, `-=` 20, `|` 10, `~` 2, `<<` 2.

- Lexer: `& | ^ ~ << >>` -> tkAmp/tkPipe/tkXor/tkLogNot/tkShl/tkShr (token
  kinds shared with the C frontend; `~` reuses tkLogNot as a shape token,
  NilPy-side meaning is bitwise not). Augassign `+= -= *= //= %= &= |= ^=
  <<= >>=` -> the tk*Eq family (`//=` maps tkSlashEq, integer division).
- Parser: Python precedence chain PyParseBitOr > BitXor > BitAnd > Shift >
  (shared ParseExpr atom, which owns comparison+arithmetic). Deviation
  guard: a tyBoolean operand adjacent to a bitwise op errors with
  "parenthesize" — Python puts comparisons LOOSER than bitwise, Pascal's
  shared layer binds them tighter, so the mixed case must be explicit
  rather than silently misparsed.
- Statements: `x op= e` and `self.f op= e` rewrite to `lhs = lhs op e`.

## Gate

test-nilpy green (+ test_nilpy_operators.npy), self-host byte-identical,
testmgr quick.
