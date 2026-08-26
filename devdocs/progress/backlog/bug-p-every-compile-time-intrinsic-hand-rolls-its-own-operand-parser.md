---
summary: "SizeOf/Low/High each re-implement operand parsing and result typing, so each accepts a different set of shapes and answers a different type -- four filed symptoms of one design"
type: bug
track: P
prio: 55
---

# Every compile-time intrinsic hand-rolls its own operand parser

**Umbrella, opened 2026-08-26.** Four tickets filed between 2026-08-20 and
2026-08-22 against `SizeOf`, `Low` and `High`. Each was filed as a missing case;
together they are one design.

## The design, stated once

`SizeOf`, `Low` and `High` do not share an operand parser or a result-typing
rule. Each is a private re-implementation of the selector chain, with its own
set of accepted shapes and its own size/bound formula:

- **`SizeOf`** has separate branches for a bare var, `v.f.g`, `v[i]` on a 1-D
  array and `v[i,j]` on an N-D one — *none of which know about `^`* — each
  carrying its own size formula. `SizeOf(p^.A)` is `Expected: ), but got: ^`.
- **`Low`/`High`** open with a flat `if CurTok.Kind <> tkIdent then Error(...)`
  in `compiler/pasparser_expr.inc`, both arms. A proc NAME escapes it only
  because a name starts with an identifier. A literal or a `(` does not.
- **`Low`/`High`** also answer the wrong *type* for a char-indexed array: the
  values are right and the type is Integer where fpc says Char, so the natural
  `for ch := Low(c) to High(c)` does not compile.
- **`SizeOf`** refuses a literal, and — this is the part that makes the umbrella
  worth reading before touching anything — routing literals through the
  expression path would be **worse than the error**: fpc types a literal by its
  VALUE (`SizeOf(1)` = 1, `SizeOf(65536)` = 4), so the expression path would
  answer 8 for most of the table, silently, and `GetMem`/`Move` would carry that
  into the allocator.

## Why this is one ticket and not four

The `SizeOf(p^.A)` ticket already reached this conclusion on its own and
recorded it: it was filed at low prio *specifically* because "the cheap version
means adding a fourth shape to `SizeOf`'s hand-rolled operand walk, which is the
structure that produced the parent bug in the first place." Its parent
(`bug-p-sizeof-an-array-field-returns-the-element-size`) was that structure
failing once already.

So the ordering is: **one operand parser and one result-typing rule for the
whole intrinsic family first**, then the four rows fall out. Doing them in the
filed order adds a fifth, sixth and seventh hand-rolled branch and makes the
eventual consolidation harder. `devdocs/dev/normalise-dont-special-case.md` is
the reference; this is a textbook instance of it.

## What NOT to normalise away

Two rules are genuinely per-intrinsic and must survive the consolidation:

1. a literal is typed by its **value** for `SizeOf` (the table in the folded
   ticket below is the spec, measured against fpc 3.2.2);
2. `Low`/`High` over a string CONSTANT are 0-based over its own length, over a
   managed-string EXPRESSION are 1-based, and over a shortstring expression are
   0-based over the DEFAULT capacity — three different bases, so "it starts with
   a quote" tells you nothing. That table is in the folded ticket too.

A consolidation that flattens either of those is a regression that compiles.

## Gate

`make compiler/pascal26` + every row of both tables diffed against fpc 3.2.2 +
`tools/gate.sh quick`.

## Progress

Three of the four rows have landed. Each was gated against fpc 3.2.2 and each
left its table pinned as a test, so the consolidation this ticket asks for now
has a spec to move against rather than a description of one.

- **`SizeOf` through a deref** — done. The walk gained a `^` arm, and measuring
  it turned up a second defect nobody had filed: `SizeOf(p^)` over a
  pointer-to-RECORD was refused outright while the same spelling over a
  pointer-to-ARRAY answered. Pinned in `test/test_sizeof_through_a_deref.pas`.
- **`High`/`Low` non-identifier operands** — done. Both arms now dispatch
  through one predicate (`HighLowOperandIsExpr` in `pasparser_name.inc`)
  instead of two copies of `if CurTok.Kind <> tkIdent then Error`. That is the
  first piece of shared operand parsing in the family. Two shortstring-
  expression rows diverge from fpc deliberately; the measurement and the reason
  are in `devdocs/dev/pascal-dialect-divergences.md`. Pinned in
  `test/test_high_low_operand_shapes.pas`.
- **`SizeOf(<literal>)`** — done, and done the way this ticket demanded: NOT by
  routing literals through the expression path, but through
  `SizeOfLiteralToken`, which types the literal by its VALUE off the token
  stream before any expression parsing happens. All 21 measured rows match fpc.
  A SET literal stays refused on purpose — fpc's own answer is inscrutable
  (`[1,2]` and `[1,200]` are both 2) and pxx bakes 32-byte masks, so any number
  chosen would be a guess that reaches `GetMem`. Pinned in
  `test/test_sizeof_of_a_literal.pas`.

**Remaining: the char/Boolean/enum-indexed `Low`/`High` result type.** The
values are right and the type is wrong (measured: pxx `97 101` / `0 1` / `0 2`
where fpc says `a e` / `FALSE TRUE` / `eA eC`). The fix needs the index type
carried on the array — `ArrTypeIdxTk`/`ArrTypeIdxEnumId` plus
`SymArrIdxTk`/`SymArrIdxEnumId`, recorded in `ParseArrayDimBounds` — and read
at **both** fold sites: `TryArrayTypeBound` in `pasparser_lval.inc` and the
variable arms in `pasparser_expr.inc`. Those two must move together or
`Low(TC)` and `Low(c)` disagree, which is the same two-mechanisms smell this
umbrella exists to remove.

---

# The folded tickets, verbatim

Each section below is a ticket that was filed separately and is now
part of this one. Nothing is summarised away: the repro tables, the
measured oracle output and the located source lines are the reason
these are worth keeping, and they are reproduced unchanged.

## `SizeOf` rejects a pointer deref in its operand

*(was `bug-p-sizeof-rejects-a-pointer-deref-in-its-operand`, prio 55)*

# `SizeOf` rejects a pointer deref in its operand

- **Type:** bug (Pascal frontend) — **Track P**
- **Filed:** 2026-08-20 (frank1-ACP), while fixing
  [[bug-p-sizeof-an-array-field-returns-the-element-size]].
- **Shared-file catch:** the fix lands in the SHARED `compiler/parser.inc`.
  Whoever takes it obeys Track A's gate and the no-concurrent-edit rule.

## Repro

```pascal
type TR = record A: array[0..2] of Integer; end;
     PR = ^TR;
var r: TR; p: PR;
begin
  p := @r;
  WriteLn(SizeOf(p^.A));    { pxx: Expected: ), but got: ^   FPC 3.2.2: 12 }
end.
```

`SizeOf(r.A)` and `SizeOf(p^)` are fine; it is the deref *inside* a selector
chain that has no case.

## Why it is filed separately, and low

It is a **loud** failure — a parse error at the exact token, not a wrong value —
which is the opposite of its parent ticket's failure mode, and nothing silently
miscomputes. It is filed at 35 rather than folded into that fix because the cheap
version means adding a fourth shape to `SizeOf`'s hand-rolled operand walk, which
is the structure that produced the parent bug in the first place.

## The shape worth considering first

`SizeOf`'s operand parser is a private re-implementation of the selector chain:
separate branches for a bare var, `v.f.g`, `v[i]` on a 1-D array, and `v[i,j]` on
an N-D one, none of which know about `^`, and each carrying its own size formula.
The parent ticket already collapsed the field formula into `RecFieldByteSize`.
The real fix is probably to stop hand-rolling: parse the operand with the ORDINARY
lvalue parser (which handles `^`, indexing, chains and casts already) in a
non-evaluating mode, and ask the resulting node for its type + extent. That is a
bigger change than this symptom justifies on its own, which is why this sits in
backlog rather than being squeezed in — but it is the version that would also
retire the `wrong number of array subscripts` and `SizeOf: unknown field` special
cases. See `devdocs/dev/root-cause-over-microfix.md`.

## `Low`/`High` of a char-indexed array answer the ordinal, not the char

*(was `bug-a-low-high-of-a-char-indexed-array-answer-the-ordinal`, prio 48)*

# `Low`/`High` of a char-indexed array answer the ordinal, not the char

Found 2026-08-22 alongside
[[bug-a-low-high-of-an-ordinal-variable-answer-0-and-minus-1]] and split out of
it, because it is a different missing fact rather than a missing arm.

## The measurement

`fpc -Mobjfpc -O1` 3.2.2 vs pxx `0b77e2bea`.

```pascal
type TC = array['a'..'e'] of Integer;
var c: TC;
```

| expression | fpc | pxx |
| --- | --- | --- |
| `WriteLn(Low(c))` | `a` | **97** |
| `WriteLn(High(c))` | `e` | **101** |
| `WriteLn(Low(TC))` | `a` | **97** |
| `WriteLn(High(TC))` | `e` | **101** |

The VALUES are right; only the type is. The consequence is that the natural
loop does not compile:

```pascal
var ch: Char;
for ch := Low(c) to High(c) do ...    { pxx: bound is Integer, not Char }
```

Note this is NOT the case of a named char SUBRANGE, which is already correct:
`TL = 'a'..'e'` gives `'a'`/`'e'` for both the type name and a variable, because
`SymIsSub`/`AliasIsSub` carry the base type along with the bounds.

## Root cause

An array's INDEX type is not recorded. `ArrTypeDimLo`/`ArrTypeDimSpan` (and
`SymArrDimLo`/`SymArrDimSpan` for a variable) store the bounds as plain
Integers, so by the time `Low`/`High` folds there is nothing left saying the
index was a Char, a Boolean or an enum. Both fold sites therefore stamp
`Ord(tyInteger)` on the literal.

Boolean- and enum-indexed arrays have the same shape and are worth checking in
the same pass (`array[Boolean] of T`, `array[TEnum] of T`) — the ordinal values
0/1 and 0..n happen to be indistinguishable from the right answer when printed
through `Ord`, so they may be silently wrong in the same way.

## The fix

Record the index type kind next to the bounds — an `ArrTypeIdxTk` parallel to
`ArrTypeDimLo`, and the matching `SymArrIdxTk` — then have both fold sites use
it instead of `tyInteger`. `TryArrayTypeBound` already returns through a `var`
parameter and the variable arms already build the literal by hand, so both take
a type the same way `TryOrdinalVarBound` already does.

**Fix both arms together.** The type-name arm currently answers 97 *on purpose*,
to agree with the variable arm; changing one without the other would make
`Low(TC)` and `Low(c)` disagree, which is worse than the present state.

## Gate

The four rows above matching `fpc -O1`, plus `for ch := Low(c) to High(c)`
compiling with a Char loop variable, plus the Boolean- and enum-indexed cases,
and self-host byte-identical.

## `High`/`Low` refuse every non-identifier operand

*(was `bug-p-high-and-low-refuse-every-non-identifier-operand`, prio 30)*

# Refused today, legal in fpc 3.2.2

```pascal
var s: AnsiString;
begin
  s := 'qxy';
  WriteLn(High('abc'));      { fpc: 2   pxx: High: expected array variable or ordinal type }
  WriteLn(High('ab' + s));   { fpc: 5   pxx: same error }
  WriteLn(High(('ab')));     { fpc: 1   pxx: same error }
  WriteLn(Low('abc'));       { fpc: 0   pxx: Low: expected array variable or ordinal type }
  WriteLn(Low('ab' + s));    { fpc: 1   pxx: same error }
end.
```

`compiler/pasparser_expr.inc`, both arms:

```pascal
if CurTok.Kind <> tkIdent then Error('High: expected array variable or ordinal type');
```

A proc NAME already escapes this (it starts with an identifier — fixed by
`compat-pascal-index-a-function-call-result`), so `High(F)` works. A literal or a
`(` does not.

# Why this is not a one-line widening — THREE bases

Measured, and this is the whole reason the ticket exists:

| operand | fpc `Low` | fpc `High` | why |
| --- | ---: | ---: | --- |
| `'abc'` | 0 | 2 | a string CONSTANT is an array-of-CHAR constant, 0-based over its own length |
| `('ab')` | 0 | 1 | …and the parens do NOT change that — so the test must ask the NODE, not the token |
| `'ab' + s` | 1 | 5 | a managed-string EXPRESSION, 1-based over its length |
| `'ab' + 'cd'` | 1 | 4 | two literals concatenated are an ANSISTRING expression, not a char array |
| `sh + 'x'` (`sh: string[10]`) | 0 | 255 | a shortstring EXPRESSION, 0-based over the DEFAULT capacity |

So "it starts with a quote" tells you nothing; the answer depends on the value's
type and on whether it is a constant. The bases themselves already exist in the
compiler after
[[bug-p-high-and-low-of-a-string-are-off-by-one]] — managed = `1 .. Length`,
frozen = `0 .. capacity`, array = own bounds. What this ticket adds is
(a) letting the operand parse, and (b) an `ASTKind[valNode] = AN_STR_LIT` arm
for the constant case, which folds to `ASTSLen[valNode] - 1` / `0` and must sit
ABOVE the frozen arm (a literal's `LastExprTk` is `tyString`, so the frozen arm
would otherwise claim it and answer 255).

Do not widen the guard to "anything": `High(3)` would then reach the runtime
`Length` tail and produce garbage where it is currently a clear error. Admit
`tkString` and `tkLParen` and keep the diagnostic for the rest.

# Sibling gap in the same arm — a frozen-string RESULT has no capacity

`High(G)` where `G: TSA` returns `string[6]` answers **1** (`Length - 1`); fpc
says 6. There is no `ProcRetStrCap` row for the frozen arm to read, and
defaulting to 255 would turn a too-SMALL bound into a too-LARGE one — a loop
reading past the end rather than stopping early — so the arm currently declines
the operand rather than guessing. Adding the capacity to the proc row is a small
Track A metadata change and would close this row; do it in the same pass if the
row is easy to add, and keep the decline if it is not.

# Gate

Track P's. Every row of both tables above in a test wired into `test-core`, each
diffed against fpc 3.2.2 — including the rows that already work, since the fix
moves them onto a different path. Grep `Length`'s arm before closing: it took
the same class of fix on 2026-08-25
([[bug-p-length-of-a-string-literal-plus-anything-does-not-parse]]) and its
literal fold is the model for the `AN_STR_LIT` arm here.

## `SizeOf(<literal>)` is refused

*(was `feature-p-sizeof-of-a-literal`, prio 20)*

# `SizeOf(<literal>)` is refused

Split out of [[feature-p-sizeof-of-an-expression]] when that landed on
2026-08-22. Expression operands now work; literal operands still raise
`SizeOf: unknown type or variable`.

They were left out **deliberately**: fpc types a literal by its VALUE, not by
the type the expression parser would give it, so routing them through the new
expression path would answer 8 for most of this table — a wrong size, silently,
that `GetMem` and `Move` would carry straight into the allocator.

## The rule to implement (measured, `fpc -Mobjfpc -O1` 3.2.2)

| operand | fpc | why |
| --- | --- | --- |
| `1` | 1 | smallest type holding the value |
| `127` | 1 | |
| `128` | 1 | unsigned range, so Byte |
| `255` | 1 | |
| `256` | 2 | |
| `32767` | 2 | |
| `32768` | 2 | still Word |
| `65535` | 2 | |
| `65536` | 4 | |
| `100000` | 4 | |
| `5000000000` | 8 | |
| `-1` | 1 | ShortInt |
| `-129` | 2 | SmallInt |
| `3.5` | 4 | a real literal is **Single**, not Double |
| `'a'` | 1 | Char |
| `''` | 1 | |
| `'abc'` | 3 | its LENGTH, not a string handle |
| `nil` | 8 | pointer width |
| `[1, 2]` | 2 | the set's storage size |

Two of these are traps worth calling out: `SizeOf(3.5)` is 4 because an untyped
real constant is Single-typed for this purpose even though it would promote to
Double in arithmetic; and `SizeOf('abc')` is 3 because a string literal is typed
as its own `array[1..3] of Char`. Both look harmless to get wrong and are wrong
everywhere, so both belong in the test.

`[1, 2]` also depends on `compat-pascal-set-storage-size-is-always-32-bytes` —
our sets are 32 bytes, so that row cannot match until that ticket does. Skip it
or assert the pxx value with a comment; do not "fix" set sizing from here.

## Where the code is

`compiler/pasparser_expr.inc`, the `szIsExpr` dispatch block at the top of the
`sizeof` intrinsic. Today the first token being a literal falls through to the
name path and its error. Add a literal arm ahead of that, keyed on the token
kind, implementing the table above.

## Prio

20. Nobody writes `SizeOf(1)` in earnest — the value of the parent ticket was
type-probing an expression, and that half has landed. This is conformance
tidiness, and the wrong answer is currently a loud compile error rather than a
silent number, which is the right failure mode to wait in.

## Gate

Every row above matching `fpc -O1` (except the set row, see above), the
expression and name paths unchanged, and self-host byte-identical.
