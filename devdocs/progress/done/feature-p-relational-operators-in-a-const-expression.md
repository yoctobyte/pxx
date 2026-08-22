---
track: P
prio: 45
type: feature
blocked-by: []
status: done
owner: claude-A
commit: 0b9004cae
summary: "`const F = 1 > 0` died on the `>` — ConstEval had no relational level, stopping at `+ - or xor`, while `const B = True and False` worked, so booleans were half supported. The idiom this blocked is the portability constant, `const Is64 = SizeOf(Pointer) = 8`. Also fixes `not True` folding bitwise to -2 and printing TRUE."
---

# Relational operators in a constant expression

Found 2026-08-22 by an FPC differential sweep over less-trodden language
features (`fpc -Mobjfpc -O1` 3.2.2 vs pxx `015bbbaf2`).

## The measurement

| declaration | fpc | pxx before |
| --- | --- | --- |
| `const F = 1 > 0` | ok, TRUE | **`Expected: begin`, at the `>`** |
| `const F = (1 > 0) and (2 < 3)` | ok, TRUE | **same, at the `>` inside the parens** |
| `const F = A = 5` | ok | **refused** |
| `const F = 'a' < 'b'` | ok | **refused** |
| `const F = SizeOf(Pointer) = 8` | ok | **refused** |
| `const B = True and False` | ok, FALSE | ok |
| `const B: Boolean = True` | ok | ok |
| `const F = not True` | FALSE | **-2** |

The last row is the interesting one: it *compiled*, and answered -2. `not`
folded bitwise, `not 1` is -2, and -2 is a non-zero Boolean, so a program that
printed it got TRUE.

## Root cause

`ConstEval` was the additive level — `+ - or xor` over `ConstEvalTerm` — and
nothing sat above it. In Pascal the relational operators bind **loosest**, so
they are exactly the level that was missing; every const expression stopped at
the first `<`, `>` or second `=`.

The second half is the TYPE. This evaluator represents every ordinal as a bare
Int64 and the declaration site types the result by inspection. A bare
`True`/`False` had its own arm (added when fpjson's `TJSONArray.Create([S])`
boxed a Boolean const as `vtInteger`), and that arm's own comment noted the gap:
*"a folded boolean EXPRESSION still lands in the integer path below."*

## The fix

- **`ConstEvalAdd`** is the old body, renamed. **`ConstEval`** is now the
  relational level above it: `= <> < <= > >=`, non-associative like Pascal's.
- **`CEIsBool`** carries the boolean-ness out of band, since the value channel is
  Int64 only. A relational sets it; `and`/`or`/`xor` keep it **only when both
  operands were boolean**, so `6 and 3` stays the integer 2 and `(a>b) and (c<d)`
  is a Boolean; `not` keeps the operand's; a typecast, an arithmetic operator and
  a unary sign clear it. A Boolean-typed NAMED const sets it, so
  `const A = 1 > 0; B = A and True;` types B as Boolean too.
- **`not` follows the operand**: logical for a Boolean (1 -> 0), bitwise
  otherwise. That is the `not True` = -2 row.
- The untyped-const declaration reads `CEIsBool` immediately after its own
  top-level `ConstEval` and declares `tyBoolean`.

One parsing detail: a single-character literal followed by a relational operator
is now left to `ConstEval` rather than claimed by the char-const arm, which used
to consume `'a'` and then die on the `<`. Only length 1 — a longer literal has
no ordinal value for this evaluator to compare, so routing it here would trade
one error for another.

## Verified against fpc

All six relational operators; a char comparison; `A + 1 = 6` proving the
relational binds loosest; `SizeOf(Pointer) = 8`; `and`/`or`/`not` over booleans
and the same operators over integers staying integers (`6 and 3` = 2, `not 0` =
-1); a Boolean-typed named const propagating; the const printing as TRUE/FALSE
rather than 1/0; the const being accepted by a **Boolean parameter**, which only
happens if it was typed Boolean; and an ordinary integer const still sizing an
array. Byte-identical to `fpc -O1`.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_const_boolean_expression.pas`, 22 assertions, wired into
`test-core`.
