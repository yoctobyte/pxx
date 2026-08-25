---
track: P
prio: 48
type: bug
blocked-by: []
summary: "`Low(a)` / `High(a)` on `array['a'..'e'] of Integer` answer 97 and 101 where fpc answers 'a' and 'e', so `for c := Low(a) to High(a)` does not compile against a Char loop variable. The bound is folded as tyInteger because the array's INDEX type is not recorded anywhere."
status: backlog
---

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
