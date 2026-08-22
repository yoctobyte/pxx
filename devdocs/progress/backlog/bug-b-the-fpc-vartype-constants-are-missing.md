---
slug: bug-b-the-fpc-vartype-constants-are-missing
track: B
prio: 30
type: bug
status: backlog
blocked-by: []
summary: "`VarType(v) = varInteger` does not compile — varEmpty/varNull/varInteger/varDouble/varString/... are not declared anywhere, so the ONLY way to test a variant's type is against this RTL's private 0..6 tags, which are not FPC's numbers either (FPC: varString = 256, varInteger = 3)."
---

# The `var*` VarType constants are missing, and the tags are ours

```pascal
uses Variants;
var v: Variant;
begin
  v := 1;
  WriteLn(VarType(v) = varInteger);     { error: undefined variable (varInteger) }
end.
```

`VarType` is declared and returns a `TVarType`, but the constants every caller
compares it against are not: `varEmpty`, `varNull`, `varSmallInt`, `varInteger`,
`varSingle`, `varDouble`, `varBoolean`, `varString`, `varOleStr`, `varVariant`,
`varInt64`, `varUString`. Delphi and FPC code that inspects a variant's type is
written with these and cannot compile.

## Two halves, and the second is the interesting one

**The constants are missing** — that part is one declaration block.

**The NUMBERS are ours, and they are not FPC's.** This RTL tags variants 0..6
(`VT_EMPTY`=0, `VT_INT`=1, `VT_INT64`=2, `VT_DOUBLE`=3, `VT_BOOL`=4,
`VT_CHAR`=5, `VT_STRING`=6). FPC/OLE uses `varEmpty`=0, `varNull`=1,
`varSmallint`=2, `varInteger`=3, `varSingle`=4, `varDouble`=5, `varBoolean`=11,
`varString`=256. Measured on fpc 3.2.2: `v := 1` gives 16 (`varShortInt` — FPC
narrows the literal), `v := 'a'` and `v := c` both give 256.

So declaring `varInteger = 3` on top of the current tags would make the program
above compile and answer **wrong**, which is worse than not compiling. The two
honest options:

1. **Map at the boundary.** Keep the internal 0..6 tags and have `VarType`
   translate to the OLE numbers, with the `var*` constants declared as OLE's.
   Everything internal (`IsTextTag`, `VarCompareValue`, the builtin helpers)
   keeps using raw tags; only the public predicate converts. Cheapest, and it
   makes `VarType(v) = varString` mean what a reader expects.
   *Caveat:* FPC's own answer depends on the literal's width (16 for `v := 1`,
   not 3), so exact parity on the numeric rows needs a decision about whether
   PXX narrows literals the same way. `varString` and `varNull` are unambiguous
   and are what real code tests.
2. **Renumber the internal tags to OLE's.** Touches the builtin helpers, six
   backends' emitted tag comparisons, and every `VType = 5` literal in
   `builtin.pas`. Bigger, and buys nothing option 1 does not.

**Recommended: 1**, and file the literal-width question as a Track U `decide-`
if it turns out real code depends on it.

`VarIsNull`, `VarIsStr`, `VarIsFloat`, `VarIsEmpty` already exist and answer
correctly, so most programs have a working spelling today — this ticket is about
the ones that test the type directly.

Track B (the constants and `VarType` live in `lib/rtl/variants.pas`); becomes a
Track A ticket only if option 2 is ever chosen.

Found by the Variant differential family, 2026-08-22, alongside
[[bug-a-a-char-variant-converts-to-its-ordinal-not-its-text]] (fixed).

## Gate

Track B's (`make lib-test`), plus a test comparing `VarType` against the named
constants for null / string / double / boolean, and one confirming `VarIsStr`
and friends still agree with it.
