---
track: P
prio: 70
type: bug
blocked-by: []
status: done
owner: claude-A
commit: fa549a775
summary: "`Low(x)` / `High(x)` over ANY ordinal variable answered 0 and -1 — Byte, SmallInt, Char, Boolean, Integer, an enum, a named subrange, all of them. `for i := Low(x) to High(x)` therefore ran ZERO times, silently, because 0..-1 is a legal empty range. Also fixed: Low/High of a named ARRAY TYPE, which was `undefined variable`."
---

# `Low(x)` / `High(x)` of an ordinal variable answer 0 and -1

Found 2026-08-22 by an FPC differential sweep over arrays (`fpc -Mobjfpc -O1`
3.2.2 vs pxx `0b77e2bea`). Two defects in the same pair of intrinsics; fixed
together because the second one is what led to the first.

## The measurement

Every ordinal VARIABLE, no exceptions:

| variable | fpc | pxx before |
| --- | --- | --- |
| `b: Byte` | 0 .. 255 | **0 .. -1** |
| `sm: SmallInt` | -32768 .. 32767 | **0 .. -1** |
| `n: Integer` | -2147483648 .. 2147483647 | **0 .. -1** |
| `ch: Char` | 0 .. 255 | **0 .. -1** |
| `bo: Boolean` | 0 .. 1 | **0 .. -1** |
| `en: TEnum` | 0 .. 2 | **0 .. -1** |
| `si: TSubInt = 3..7` | 3 .. 7 | **0 .. -1** |
| `sc: TSubChar = 'a'..'e'` | 97 .. 101 | **0 .. -1** |

And every named ARRAY TYPE:

| operand | fpc | pxx before |
| --- | --- | --- |
| `Low(TArr)` / `High(TArr)`, `TArr = array[5..9] of Integer` | 5 / 9 | **`undefined variable (TArr)`** |
| `Low(TArr2D)` / `High(TArr2D)`, 2-D | 0 / 2 (first dim) | **`undefined variable`** |
| `Low(TDyn)` | 0 | **`undefined variable`** |
| `High(TDyn)` | compile error | compile error (agrees) |

The array-VARIABLE arms were already correct and stayed correct.

## Root cause

**0 and -1 is not a random wrong pair.** It is `Length(x) - 1`, reached through
the fallback at the bottom of both intrinsics in `compiler/pasparser_expr.inc`:

```pascal
else
begin
  node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength);
  ...  { Length(x) - 1 }
end;
```

A scalar has no `[data-8]` length header, so the runtime `Length` path answers
0 and `High` answers -1. `Low`'s fallback is the literal `else ASTIVal := 0`.
Both intrinsics had arms for a 1-D static array, an N-D static array and a
fixed record-field array — the shapes people had tripped over — and nothing at
all for the operand type the intrinsic is most often written against.

That is the interesting part: **the wrong answer is a legal empty range**, so
the canonical loop

```pascal
for i := Low(x) to High(x) do ...
```

compiles, runs, does nothing, and reports no error. `High(b)` used as a mask or
an allocation bound was -1 for the same reason. This is the failure mode
`devdocs/dev/root-cause-over-microfix.md` calls the expensive one: not a crash
with a location, but a plausible value far from the cause.

The type-name half is a different miss: `TryFoldHighLowType` and
`TryConstHighLowValue` handled ordinal names, subrange aliases and enum types,
and simply had no arm for `FindArrayType`.

## The fix

Two helpers in `compiler/pasparser_lval.inc`, each called from both places that
need it rather than copied — the two `TryConst…`/`TryFold…` functions already
carry a comment saying they are one concept in two places, so a third copy was
not on:

- **`TryOrdinalVarBound(symIdx, wantHigh, var v, var tkOut)`** — a named
  subrange answers `SymSubLo`/`SymSubHi` (already stamped for `{$R+}` and never
  consulted here), an enum answers `EnumTypeOrdRange(SymEnumId[...])`, anything
  else answers `OrdinalTypeBound(Syms[].TypeKind, ...)`. Hooked into both
  intrinsics as an arm ahead of the `Length` fallback.
- **`TryArrayTypeBound(nm, wantHigh, var v)`** — a fixed array type answers its
  first dimension's bounds from `ArrTypeDimLo`/`ArrTypeDimSpan`; a dynamic type
  answers 0 for `Low` and is **refused** for `High`, matching fpc. Refusing
  matters: answering whatever `ArrTypeHi` held would put a wrong upper bound in
  the very loop this ticket is about.

`tkOut` carries the bound's TYPE back, so the folded literal prints like fpc's:
`Low(Char)` is `#0` and not `0`, `Low(Boolean)` is `FALSE` and not `0`,
`Low(sc)` is `'a'`. Asserted directly (`Low(ch) = #0`, `Low(bo) = False`).

## Known remaining divergence, deliberately matched to the variable path

`Low`/`High` of a **char-indexed array** answers the ordinal, not the char:
`array['a'..'e'] of Integer` gives 97/101 where fpc gives `'a'`/`'e'`. That is
the array path's divergence and it predates this ticket — the VARIABLE arm has
always answered 97. The new type-name arm answers 97 too, on purpose: a type
name and a variable of that type disagreeing would be worse than either answer.
Filed as `bug-a-low-high-of-a-char-indexed-array-answer-the-ordinal`, which
should fix both arms in one change.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_low_high_of_ordinal_and_array_type.pas` — 45 assertions, output
identical to `fpc -O1`'s on the same source, wired into `test-core`. It also
asserts every previously-working arm (array variable, dynamic variable, empty
dynamic variable answering -1 legitimately) so the new arms cannot have
displaced them.
