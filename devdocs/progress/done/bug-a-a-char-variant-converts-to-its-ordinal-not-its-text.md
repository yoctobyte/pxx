---
slug: bug-a-a-char-variant-converts-to-its-ordinal-not-its-text
track: A
prio: 55
status: done
commit: 189ca5410
---

# One value, two spellings, two numbers

```pascal
var v: Variant; s: string; i: Integer;
begin
  v := '7';                 i := v;   { pxx: 55    fpc: 7 }
  s := '7'; v := s;         i := v;   { pxx:  7    fpc: 7 }
end.
```

55 is the character code of `'7'`. A one-character string **literal** is boxed
as `VT_CHAR`; a string **variable** as `VT_STRING`. `VariantToInt64` had tag 5
sitting in the integer branch —

```pascal
else if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 5) then
  Result := p^.Payload
```

— so the char tag answered its payload raw, while `VT_STRING` two branches down
parsed its text. Same for `VariantToDouble`.

## Why this is a bug and not a dialect choice

There IS a dialect choice nearby, and it was made deliberately: PXX keeps
`Char(v) = Chr(n)` where FPC renders the variant and takes character 1
(`bug-p-variant-to-int-and-char-conversion-diverges-from-fpc`, decided by the
user 2026-08-13, FPC's rule available behind `--strict-fpc`). So "a char variant
is numeric" is a defensible position and one might expect this row to follow it.

It cannot, for a reason that has nothing to do with which model is nicer: **the
two spellings of one value disagreed.** No dialect can hold that. Once they must
agree, the question is only which way, and then FPC is not a tie-breaker but the
whole answer — **FPC has no char variant at all.** Measured:

```pascal
c := 'a'; v := c;
VarType(v) = 256      { varString }
VarIsStr(v) = TRUE
i := v                { raises EVariantError }
```

So text it is, on every row: `'7'` parses to 7 whether written as a literal, a
variable or a real `Char`, and `'a'` raises exactly as `'abc'` already did.

## The RTL said both things too

`lib/rtl/variants.pas` had the same split, four lines apart:

```pascal
function VarIsStr(const V: Variant): Boolean;
begin
  Result := VarType(V) = 6;                              { string only }
end;

{ text tag: a char and a string are one kind here ... }
function IsTextTag(t: TVarType): Boolean;
begin
  Result := (t = VT_STRING) or (t = VT_CHAR);            { both }
end;
```

The comparator used `IsTextTag` and the public predicate used the bare `= 6`, so
the unit gave two different answers to two different callers. `VarIsStr` now
uses the same rule, and reports True for a char variant — which is also FPC's
answer.

`normalise-dont-special-case`: the concept is "is this variant textual", and it
existed three times (twice in the RTL, once as a tag test in the builtin) with
two answers.

## Scope — what this does NOT fix

Two further FPC divergences were measured in the same sweep and are **filed
separately, not fixed here**, because each is a different mechanism:

- **Mixed-tag comparison.** `a := 1; b := '1'; a = b` answers False; FPC coerces
  and answers True. `PXXVarBinOpPas` coerces stringy operands for arithmetic
  (`isCompare = 0`) and not for comparison, and x86-64 hand-emits its own copy
  of the whole rule in `EmitVarBinOp`. → `bug-a-a-variant-comparison-does-not-coerce-a-stringy-operand`
- **Null propagation.** `Null + 5` should be Null; PXX treats Null as 0.
  → `bug-a-null-does-not-propagate-through-variant-arithmetic`

## Verification

`test/test_char_variant_converts_as_text.pas`, 10/10, identical under fpc 3.2.2:
literal / variable / real `Char` spellings, `Int64` and `Double` targets, the
two-character control that always worked, the raise on a non-numeric character,
`VarIsStr` on both spellings, and the round trip back to a string.

Touches `lib/rtl/variants.pas` (Track B ground) as well as
`compiler/builtin/**`. Done in one change deliberately: `VarIsStr` is not a
separate defect, it is the same question answered in the other file, and
splitting it would have shipped a compiler that says "text" and an RTL that says
"not text" for the same variant.

Found by the Variant differential family.

Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN.
