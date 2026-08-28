---
slug: bug-b-the-fpc-vartype-constants-are-missing
track: B
prio: 55
type: bug
status: done
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

## RESOLVED 2026-08-28 (frankB) — option 1 (map at the boundary), taken together with its two siblings

**All three variant tickets were one job, and doing this one alone would have
made the other two worse.** Resolved together:

- this ticket [p55] — the constants are missing, and the numbers are ours;
- `feature-b-vartype-speaks-fpc-varxxx-codes` [p45] — **the same defect**,
  re-filed on 2026-08-25 after `decide-vartype-returns-pxx-tags-not-fpc-codes`
  chose option A. That ticket is the decided spec and this one is the finding
  that produced it; they were ranked ten points apart in the same lane;
- `bug-b-varisstr-is-false-for-a-one-character-string` [p45] — already fixed in
  the code, and now guaranteed by construction. See below.

### Why they could not be done separately

`VarIsClear`, `VarIsEmpty`, `VarIsNull`, `VarIsNumeric`, `VarIsStr`, `VarToStr`,
`VarToStrDef` and `VarCompareValue` all called `VarType(V)` and compared the
result against an internal tag. Translating `VarType` **without** touching them
would not have left them merely stale — it would have broken every one: after
the change `VarType` answers 256 for a string, so `VarType(V) = VT_STRING`
(6) is false for *all* strings, not just the one-character case the third ticket
reports. Fixing the headline ticket alone turns a narrow known bug into a total
one.

**The ticket's own site list was short, and the missing part was invisible to
the obvious search.** `feature-b-vartype-speaks-fpc-varxxx-codes` names "the
four internal call sites that compare against `VT_` constants (lines 185, 203,
255, 261)". There are eight, because `VarIsEmpty` and `VarIsNull` compared
against a bare `0` and `VarIsNumeric` against bare `1`/`2`/`3` — **a grep for
`VT_` cannot see a raw literal.** Same family as the `ls lib/rtl/mimic_*` check
that called `codecs` missing this morning: a search on the artifact's *name*
instead of on the behaviour.

### What landed

`lib/rtl/variants.pas` only — no compiler change, as the decision required.

- FPC's `varXxx` constants exported, **measured from fpc 3.2.2 by printing
  them**, not transcribed. The set is irregular — `varBoolean` = 11, the sized
  integers start at 16, `varString` = 256, `varUString` = 258 — and a guessed
  constant would have looked plausible and been wrong.
- A private `RawTag(V)` reads the internal tag. It is now the **only** thing in
  the unit that may be compared against a `VT_` constant, and all eight call
  sites use it.
- `VarType` translates internal tag to FPC code at the facade seam, per the
  standing policy in `decide-rtti-kind-numbering` and
  `decide-classinfo-returns-our-blob-or-nothing`: the RTL facade speaks FPC's
  public numbering, the compiler's tags stay ours and stay private.
- An unknown tag answers `varError` (10), not `varEmpty` — `varEmpty` would be a
  lie that reads as "no value".

### Measured against fpc 3.2.2: 11 of 12 rows now identical

The one divergence is `v := 1` → `varInteger` (3) where FPC says `varShortInt`
(16), because **FPC narrows an integer literal to the smallest type that holds
it** and pxx has one integer tag. The line real code writes — `v := someInteger`
— agrees with FPC exactly, and the test asserts that row immediately next to the
divergent one so the two cannot be confused. Recorded in
`devdocs/dev/pascal-dialect-divergences.md`; **not** filed as a Track U
literal-width question, because chasing it means narrowing integer literals at
assignment, which is a language change to buy parity on a value that varies with
the literal rather than with the program's meaning — and `CLAUDE.md` is explicit
that we do not chase 100% FPC parity.

### The third ticket is fixed by construction, not by a second patch

Both text tags fold onto `varString`, so `VarType(v) = varString` is true for
`'x'` as well as `'xy'`. **FPC has no char variant at all** (`v := c` with
`c: Char` reports 256 there too — measured), so the fold is parity rather than a
compromise, and it deletes the class of bug rather than the instance: a caller
can no longer observe that `'x'` and `'xy'` are tagged differently, which is the
only reason `VarIsStr` could disagree with `VarCompareValue` in the first place.
`VarIsStr` itself had already been corrected in the source at some earlier point
— its ticket was simply never closed.

### Test and gate

`test/lib_variants_vartype_codes.pas`, wired into `make lib-test`, sentinel
`VARTYPECODES OK`. It asserts all 25 constants, every `VarType` row against
FPC's measured answer, and — the actual regression risk — that **every predicate
agrees with the code its own unit reports**, since the predicates read the
private tag while `VarType` returns FPC's numbering.

**Negative control:** reverting `VarType` to return the raw tag fails the test
with 11 errors, on exactly the 11 `VarType` rows.

`make lib-test` REAL EXIT=0 (redirected, not piped). It went red once on an
unrelated intermittent in `lib_dns_libc`, which did not reproduce in a full
re-run or 15 direct runs and is filed as
`bug-b-lib-dns-libc-failed-once-in-the-gate-and-claims-a-hermeticity-it-lacks`.
Synapse jobs skipped, same standing caveat.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
