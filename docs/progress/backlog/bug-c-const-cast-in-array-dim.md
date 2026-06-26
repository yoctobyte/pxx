# C: `(type)` cast inside a constant expression (array dimension)

- **Type:** bug — Track C (const-expr evaluator)
- **Opened:** 2026-06-26
- **Found-by:** lua ltable `unsigned int nums[MAXABITS + 1]`, where
  `MAXABITS = cast_int(sizeof(int) * CHAR_BIT - 1)` = `((int)(...))`.

## Symptom
`int a[(int)4];` -> parse error ("Expected ], got ("); `enum { X = (int)7 }` also
mis-folds. `CEvalConstPrimary` (cparser.inc) treats `(` only as grouping, never as
a cast, so the cast type tokens are not skipped and the operand is not folded.

## Attempt + open puzzle (read before retrying)
Added a cast branch to CEvalConstPrimary's tkLParen case: if `IsCTypeTok` after
`(`, skip the type tokens to the matching `)` then fold the operand with
CEvalConstPrimary. The grouping path `(2+3)` stayed correct, but the ARRAY
dimension still failed: a debug at the local-array dim (`arrLen := CEvalConstExpr`)
showed CurTok = tkLParen (74) BEFORE the call yet `arrLen = 0` and CurTok = 2
AFTER — i.e. CEvalConstExpr returned without folding the cast even though the same
CEvalConstPrimary edit folded an enum value. Two different behaviours from the one
function = something context-dependent (token-kind numbering? a second const path?
IsCTypeTok state?). REVERTED rather than ship an inconsistent/partial const-eval.

## Fix direction
Pin why the local-array-dim CEvalConstExpr path and the enum path diverge (add the
debug back: print Ord(CurTok.Kind) + CurTok.SVal at entry of CEvalConstPrimary and
at the local-array dim; compare the two call sites). Then handle `(type)expr` once
in CEvalConstPrimary. Note a SEPARATE token-based struct-field array-dim evaluator
at cparser.inc ~2591 only reads tkInteger and must also learn casts/`/`. Common:
lua MAXABITS / cast_int / luaM_limitN array sizes.
