---
track: B
prio: 45
type: bug
blocked-by: []
summary: "VarIsStr answers FALSE for a ONE-CHARACTER string variant. It tests `VarType(V) = 6` (VT_STRING) and a single char is tagged VT_CHAR = 5, so `v := \'x\'; VarIsStr(v)` is False while `v := \'xy\'` and `v := \'\'` are both True. The same unit already has the right predicate three lines below — IsTextTag(t) = (t = VT_STRING) or (t = VT_CHAR) — and VarCompareValue uses it and gets the one-char case right. Two mechanisms for one concept, disagreeing."
---

# `VarIsStr` is False for a one-character string variant

- **Type:** bug (silent wrong answer) — Track B (`lib/rtl/variants.pas`)
- **Status:** done
- **Opened:** 2026-08-22, by a 30-program Variant differential against fpc 3.2.2

## Measured

```pascal
uses SysUtils, Variants;
var v: Variant;
begin
  v := 'x';  WriteLn(VarIsStr(v), ' tag=', VarType(v));
  v := 'xy'; WriteLn(VarIsStr(v), ' tag=', VarType(v));
  v := '';   WriteLn(VarIsStr(v), ' tag=', VarType(v));
end.
```

| | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `'x'` | True | **False** (tag 5) |
| `'xy'` | True | True (tag 6) |
| `''` | True | True (tag 6) |

The length of the string decides the answer, which no caller could guess.

## Root cause, and the shape it is an instance of

```pascal
function VarIsStr(const V: Variant): Boolean;
begin
  Result := VarType(V) = 6;          { VT_STRING only }
end;

{ text tag: a char and a string are one kind here ... }
function IsTextTag(t: TVarType): Boolean;
begin
  Result := (t = VT_STRING) or (t = VT_CHAR);
end;
```

Those two sit **three lines apart** in the same file and answer the same
question differently. `IsTextTag` is the correct one — its own comment says so
outright — and `VarCompareValue` uses it, which is why comparing a one-char
variant as text works while asking whether it IS text does not.

Two mechanisms serving one concept is the smell
`devdocs/dev/normalise-dont-special-case.md` is about, and this is its cheapest
possible form. Note also that `VarIsStr` spells the tag as a bare `6` where the
whole rest of the unit uses the named `VT_STRING`, which is how it escaped the
notice that `VT_CHAR` exists.

## Fix

```pascal
Result := IsTextTag(VarType(V));
```

`IsTextTag` is declared in the implementation section below `VarIsStr`, so
either move it up or forward-declare it.

**Check the siblings in the same pass**, since the same bare-number habit could
have hit them: `VarIsNumeric` (does it accept VT_INT64 and VT_DOUBLE as well as
VT_INT?) and any other `VarType(V) = <literal>` in the unit. Grep for
`VarType(V) =` and make every one of them use a named constant or a predicate.

## Not part of this

`VarType`'s numbers do not match FPC's `varXxx` — that is deliberate and
documented in the unit header, and
[[decide-variant-tag-space-is-a-language-wide-commitment]] settled it
(the tag set is ours, closed, and not a durable format). FPC code comparing
against `varString` fails to COMPILE here rather than silently mis-branching,
because this unit does not declare those constants. Do not "fix" that.

## Gate

Track B's: build with `$(PXX_STABLE)` (working again as of the v373 pin),
`make lib-test`. Plus the three rows above matching fpc 3.2.2, one-char case
included.

## RESOLVED 2026-08-28 (frankB) — landed as part of one job

Done together with `bug-b-the-fpc-vartype-constants-are-missing`, which carries
the full write-up. The three tickets were one defect and one already-fixed twin,
and doing the headline one alone would have broken this one rather than left it
stale: after `VarType` translates, a comparison against an internal `VT_` tag is
false for *every* value of that kind, not just the reported case.

Landed in `lib/rtl/variants.pas` only, no compiler change: FPC's `varXxx`
constants exported (measured from fpc 3.2.2, not transcribed), a private
`RawTag` for the eight internal call sites, and `VarType` translating at the
facade seam. 11 of 12 rows now match FPC exactly; the documented divergence is
`v := 1` (FPC narrows the literal to `varShortInt`).

Gated by `test/lib_variants_vartype_codes.pas` in `make lib-test`, sentinel
`VARTYPECODES OK`, negative-controlled.

## Log
- 2026-08-28 — resolved, commit fb75a3d57.
