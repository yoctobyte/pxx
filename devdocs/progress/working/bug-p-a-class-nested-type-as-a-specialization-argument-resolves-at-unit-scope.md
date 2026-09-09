---
track: P
prio: 60
type: bug
blocked-by: []
status: working
owner: frankZ
summary: "A type named as a SPECIALIZATION ARGUMENT is resolved where the template body materialises, not where the source wrote it. THREE DOORS -- three ways to be in neither table NestedSpecArg consults. Door A (a non-generic class, its own or a non-generic ancestor's nested type) is fixed at 3a89c6184; door C (inherited from a GENERIC ancestor, the rtl-generics shape) at 61a9463be; door B (the template's own body) always worked. The silent arm answers 300 where it answered 44. Every ladder row now passes except v7, which is bug-p-a-qualified-type-name-cannot-be-a-generic-argument and unchanged. Two regression tests, both byte-matching fpc 3.2.2, both with a clean negative control on a pre-fix binary. STILL OPEN, and it is one question: the Generics.Collections driver compiles end to end (11 errors, 6m59s) where it used to abort, and of its 8 `TEnumerator` mints seven now resolve while exactly ONE is bare `alias=TEnumerator$PT` -- which site produces it is unidentified, and the one experiment that looked like it would answer that made the corpus worse and settled nothing. SEPARATE, filed, and NOT a blocker: bug-p-a-hoisted-nested-type-name-leaks-between-two-specializations-of-one-template, a PRE-EXISTING leak verified on a binary without either fix, which is why both tests here instantiate each template once."
---

# A class-nested type as a specialization argument resolves at unit scope

**The 15-line repro. fpc 3.2.2 accepts and runs it; pxx refuses it.**

```pascal
program v5;
{$mode delphi}
type
  TEnum<T> = class
    function Cur: T; virtual; abstract;
  end;
  TDerived = class
  public type
    PT = ^Integer;
  protected
    function GetPtrEnum: TEnum<PT>;
  end;
function TDerived.GetPtrEnum: TEnum<PT>; begin Result := nil; end;
var a: TDerived;
begin a := TDerived.Create; WriteLn('ok'); end.
```

```
pascal26:5: error: unknown type: PT
  near:   class function Cur : >>> PT ; virtual
```

**Line 5 is `TEnum<T>`'s own body, not the use site** — the substituted template
body carries the argument's SPELLING and is re-parsed where that spelling does
not resolve.

## THE SILENT ARM IS THE EXPENSIVE ONE, AND IT IS NOT A COMPILE ERROR

Give the unit a namesake and the refusal becomes a wrong answer.

```pascal
type
  TElem = Byte;                { unit-scope namesake -- a DIFFERENT type }
  TBox<T> = class V: T; function Size: Integer; end;
  TDerived = class
  public type
    TElem = Int64;             { the one the source MEANT }
  public
    function MakeBox: TBox<TElem>;
  end;
...
  Result := TBox<TElem>.Create; Result.V := 300;
```

| | pxx (417ee5636a72) | fpc 3.2.2 |
| --- | --- | --- |
| `Size` | 8 | 8 |
| `V` | **44** | **300** |

44 is 300 mod 256. The value was stored through the unit-scope `Byte`.

**And `Size` is the readout that hides it.** Both compilers answer 8 because the
readout casts to `TBox<Int64>` and reports the CAST's view; only the VALUE
separates them. That is the "could the way I am printing this turn a
disagreement into an agreement" trap in CLAUDE.md, hit here with a size probe
that looked like the natural instrument. Assert the value, not the width.

## THE LADDER — ten variants, all re-measured at `1c16d4523` / binary `417ee5636a72`

Re-measured after `1c16d4523` ("a specialized body now materialises where the
specialization is visible") landed, because that fix is adjacent and every row
below would otherwise be a claim about a binary that no longer exists. Nothing
moved.

| | shape | pxx | fpc |
| --- | --- | --- | --- |
| v1 | inherited nested type used PLAINLY (`function GetP: PT`) | **ok** | ok |
| v2 | inherited nested type as a SPEC ARG, generic ancestor + generic descendant | unknown type: PT | ok |
| v3 | same, ancestor NON-generic, `PT = ^Integer` concrete | unknown type: PT | ok |
| v4 | same, ancestor AND descendant both non-generic | unknown type: PT | ok |
| v5 | **no inheritance at all** — the class declares `PT` itself, non-generic | unknown type: PT | ok |
| v6 | `TElem = Integer` — a plain alias, not a pointer | unknown type: TElem | ok |
| v7 | qualified at unit level: `var a: TEnum<TDerived.TElem>` | unknown type: TDerived | ok |
| v8 | v6 plus a unit-scope namesake declared FIRST | ok | ok |
| v9 | concrete argument `TEnum<Integer>` (control) | ok | ok |
| v10 | v8 with the namesake a DIFFERENT type | ok, **v=44** | ok, v=300 |
| v11 | v6 with the namesake declared AFTER the class | unknown type: TElem | ok |

**What each row buys, because a table of passes is not an argument:**

- **v1 vs v2 is the whole finding.** The nested name resolves in a plain type
  position and does not resolve in a specialization argument. Two lookups for
  one question, and only one of them walks the class.
- **v4 and v5 delete the obvious suspects.** Inheritance is not required (v5 has
  none), the ancestor need not be generic (v3), the host class need not be
  generic (v4), and the nested type need not depend on a type parameter (v3, v6).
  Every generics-shaped explanation for this dies on v5, which is one class, one
  nested alias, no inheritance and no type parameter anywhere but the template.
- **v6 deletes "pointers".** `TElem = Integer` fails identically, so this is not
  the `PT = ^T` shape that the rtl-generics corpus makes it look like.
- **v7 says the qualified spelling is not an escape hatch** — `TEnum<TDerived.TElem>`
  fails one token EARLIER (`unknown type: TDerived`), so the argument list cannot
  parse a dotted type name at all. Anyone reaching for `Owner.Nested` as the
  workaround will find it is a second bug, not a route round this one.
- **v8 names the scope.** Adding a unit-scope namesake makes v6 compile. So the
  argument is being resolved, and it is being resolved AT UNIT SCOPE. This is the
  positive control that turns "it does not resolve" into "it resolves in the
  wrong table".
- **v9 is the row that proves the harness can pass**, and v10 is the row that
  proves it can fail for the right reason.
- **v11 names WHERE the wrong table is read** — see the mechanism section. It is
  v8 with one line moved, and it is the only row that separates the two fixes.

## The mechanism, and the part of it that is a HYPOTHESIS

Measured: `PXXDBG=p.mint:*` on v6 prints

```
PXXDBG p.mint dgen alias=TEnum$TElem tmpl=TEnum args=TElem
```

The mangled name and the substitution both carry the raw spelling `TElem`, and
`EmitSpecDecl` splices `TEnum$TElem = specialize TEnum<TElem>;` as a
prerequisite ahead of the declaration that needs it. `ParsingClassBodyCi` is -1
where those tokens are read, so `FindTypeAlias`'s `AliasVisibleHere` filter —
which is keyed on exactly that variable — cannot see a row whose `AliasOwnerCi`
is the class.

**MEASURED, and it is the expensive answer.** The question was whether the
prerequisite is hoisted ahead of the CLASS — so the nested type genuinely does
not exist yet in token order — or merely parsed with the class scope switched
off, so the row exists and the filter hides it. v4 is consistent with both. **v11
separates them:** move the unit-scope namesake from before the class to AFTER it,
same section, and v8's pass becomes a failure. So the emission point is EARLIER
than a type declared later in the same section, and the argument is resolved
ahead of the class rather than beside it with a scope flag cleared.

That kills the cheap fix. An owner column on the NSpec row plus a scope window
while those tokens are read would answer the second reading and cannot answer
this one: at the moment the argument is resolved, there is no row to make
visible. What is left is the same shape the routine arm already costed and
refused as a one-liner — hoist the nested type too, and with it whatever it
references — or instantiate at the USE site instead, which avoids the dependency
graph entirely and is the direction worth costing first. That is the same
conclusion the routine arm reached from the other end, which is a reason to
believe it and also a reason to fix the two together rather than twice.

**And it does NOT go through the splice path.** `PXXDBG=p.specsplice` (frankH,
`1c16d4523`) prints nothing at all on v6 — no splice event, because this route is
the `dgen` mint plus `EmitSpecDecl` and never pends anything. Recorded as an
exculpation with an owner: whatever this is, it is not the mechanism that
`bug-p-a-specialized-method-body-splices-into-an-illegal-place-under-circular-uses`
closed, and looking for it there is a dead end someone would otherwise take
twice.

## 2026-09-09 (frankH) — THE SLUG IS TOO NARROW: no nested type is required

frankH built four rows against the same question and the discriminating one has
no nested type in it at all:

| case | specialization argument | pxx | fpc |
| --- | --- | --- | --- |
| ctl_pre | a unit type declared BEFORE the class | compiles, `ok` | ok |
| ctl_out | the class itself, used OUTSIDE it | compiles, `ok` | ok |
| **selfref** | **the class itself, used INSIDE its own body** | **`pascal26:10: unknown type: TDerived`** | ok |
| base (this ticket) | a class-nested type, used inside | `pascal26:5: unknown type: PT` | ok |

```pascal
TDerived = class
protected
  function GetSelfEnum: TEnum<TDerived>;   { TDerived is a plain UNIT-scope name }
end;
```

`TDerived` is not nested in anything and is not private to any scope. If the
prerequisite were merely parsed with the class scope switched off, it would
resolve — so this is the same conclusion v11 reaches, from a case where the
visibility reading is not merely unlikely but impossible. Two independent
routes to the same answer, which is why it is recorded rather than folded in.

**And ctl_pre and ctl_out are what stop selfref being one broken row**:
specializing on a class is fine from outside it, and a name declared before the
class is fine from inside it. So the boundary is exactly **"declared at or after
the class's own declaration"**, and every arm in this ticket sits past it.

That WIDENS the ticket. The slug says class-nested and the population is larger:
`AliasVisibleHere` is not the lever, and neither is the Alias table — whatever
chooses the prerequisite's insertion point is. The slug is left alone because it
is cited; this section is the correction, and a reader who stops at the title
will under-scope the fix.

## Relationship to the three arms already open

`bug-p-a-specializations-concrete-argument-is-keyed-by-its-spelling-so-two-scopes-types-collide`
[p50, working, frankS] opens with the same SENTENCE — a name standing in for the
thing it names — and its class/record arm is fixed, its alias mirror is closed,
and its generic-ROUTINE arm is parked on pass order. **This is a fourth arm and
it is a different mechanism from all three**, so it is filed separately rather
than appended:

- The routine arm's wall is *"the type does not exist yet"* — a routine's local
  `type` section is parsed in pass 2 and the sweep runs in pass 1. Here the type
  **does** exist, is fully parsed, and is in the Alias table with an owner; it is
  a VISIBILITY question, not an existence one.
- The class/record arm was fixed by `SpecArgIdentity` — asking WHICH declaration
  a name denotes. That already-landed function would answer this too **if it were
  asked from inside the class**, and it is not, so this arm is about WHERE the
  question is asked rather than WHICH question.
- Its warning still applies here in full and is the reason this ticket does not
  propose the obvious fix: **do not land the visibility half alone.** v10 is that
  warning already come true in this arm — the refusal is the compile error, and
  the version of this program that compiles today is the one that gets 44.

Do not close this by adding a nested-type arm to `ParseTypeKind`'s cascade in the
argument parser. That is a second copy of a lookup, which is what
`normalise-dont-special-case.md` is about and what the routine arm's own costing
already refused.

## Provenance

Reduced from `generics.collections.pas` while driving
`feature-pascal-corpus-generics`. Whether this is that rung's blocker is **NOT
established** — see the note below; it stands on its own as an fpc-differential
defect either way.

**AND THE RUNG'S WALL IS NO LONGER `unknown type: PT` AT ALL — measured, and
attributed.** `1c16d4523` (frankH, "a specialized body now materialises where
the specialization is visible") cleared it. Revert-rebuild, not timing:

| compiler | binary | wall on `uses Generics.Collections` |
| --- | --- | --- |
| HEAD `d47ae0762` | `417ee5636a72` | `generics.defaults.pas:3250 undefined variable (TGOrdinalStringComparer)` |
| that commit's `compiler/defs.inc` + `pasparser_generic.inc` reverted to its parent, rebuilt | `4a6207c05ba2` | `generics.collections.pas:120 unknown type: PT` |

Only two ticket-only commits separate the two trees. `4a6207c05ba2` is also the
binary frankS quoted the PT wall at independently, which is a second source that
fails differently from a revert.

**WHAT THAT TABLE ATTRIBUTES, AND WHAT IT CANNOT — the row above it is one claim
and the table looks like two.** It attributes the CLEARING of `unknown type: PT`
and nothing else. It says nothing whatever about the CAUSE of
`generics.defaults.pas:3250`, and a revert-rebuild is structurally unable to:
with the fix out, the file stops at `collections:120` again and never reaches
`:3250`, so the new wall's disappearance is guaranteed and carries no
information. **A revert makes any LATER wall vanish, which reads exactly like
proof.** frankS caught the reading and it is a correction to how I wrote this,
not to the measurement: the two loops behind `:3250` are `3a011ed6f`
(2026-08-29) and `951d9c9dd` (2026-08-20), both ancestors of the reverted tree,
so `1c16d4523` made an August defect REACHABLE for the first time and did not
introduce it — the same relationship `ad7c03b03` had with the forward-pointer
bug. The discriminator for a moved wall is the CODE's age, never the error's
presence. Owned and diagnosed at
`bug-p-a-generic-method-implementation-is-attributed-by-name-not-arity`
(`a9a81a51c`, frankS).

**The ladder in this ticket survives that fix** — all nine rows re-measured at
`417ee5636a72`, nothing moved — so this is not the same defect wearing a
different face, and it is now certain that it is NOT the rung's blocker. Filed
against the corpus as provenance only.

## The bisect that produced it, and the two ways it lied

Recorded because both failure modes are cheap to repeat. Driver `uses
Generics.Collections` alone, source `/usr/share/fpcsrc/3.2.2/packages/rtl-generics/src`
(frankS has since measured that tree byte-identical to
`library_candidates/rtl-generics`, md5 `1010a887c20dc546215749ca46c5a773`, so the
two line-number sets are comparable after all — the rung's old warning that they
are not is dead).

At binary `4a6207c05ba2`, truncating the interface at line N and appending
`implementation end.`:

- cut 163 **compiles** — and it contains every declaration the wall looks like it
  is about: `TEnumerable<T>` with `public type PT = ^T` and
  `GetPtrEnumerator: TEnumerator<PT>` at :133, `TCustomPointersEnumerator<T, PT>
  = class abstract(TEnumerator<PT>)` at :144, `TCustomPointersCollection<T, PT>`
  at :146, `TEnumerableWithPointers<T>` at :157. **The declaration region is not
  the defect.**
- cut 466 compiles; cut 469 compiles; **cut 470 reproduces** — :470 is the single
  line `{$I inc\generics.dictionariesh.inc}`.

**LIE ONE — a truncation artefact wearing the shape of a verdict.** Cuts 200,
300 and 400 fail with `unexpected token in a unit interface section` at N+4, and
a bisect that treats any failure as reproduction reports "nothing reproduces",
which is what this one did on its first pass. Cuts at or below 163 fail with
`--emit-obj: this object would define no linkable symbol`, which is the
truncation's link artefact and means the file COMPILED. Neither error is about
the tree.

**LIE TWO — the instrument moved mid-sweep, in the hands of someone who had just
written the rule down.** The bisect INSIDE the include ran cuts 40-200 on
`4a6207c05ba2` and cuts 230-656 on `417ee5636a72`, because a pull-and-rebuild
happened between them. The tell was that cut 656 — the WHOLE include, i.e. the
unmodified file — did not reproduce. That table is withdrawn, not corrected:
half of it is a statement about a binary that no longer exists. **PUSH -> LET THE
PULL SETTLE -> REBUILD -> MEASURE has a fourth failure mode nobody had written
down: rebuilding CORRECTLY, in the middle of a sweep, is still moving the
instrument.** The rule reads as being about starting from a stale tree; the
hazard is any rebuild inside the measurement, including the one the rule tells
you to do.
**So the ladder above is an independently-reproducible defect and NOT yet shown
to be the rung's blocker.** Those are two claims and only the first is measured.

## 2026-09-09 (frankS) — a TENTH variant: the same defect through INHERITANCE, and one arm of it already works

Measured at binary `417ee5636a72`, HEAD `5acbe362b`. Two rows, and the pair is the
boundary:

```pascal
{ F — the nested type is declared in the SAME template that is specialized }
TEnum<T> = class abstract function Get: T; virtual; abstract; end;
TWithPointers<T> = class abstract
public type
  PT = ^T;
protected
  function GetPtrEnum: TEnum<PT>; virtual; abstract;
end;
TIntList = class(TWithPointers<LongInt>) end;          { COMPILES }

{ E — identical, except PT is INHERITED from an ancestor template }
TEnumerable<T> = class abstract public type PT = ^T; end;
TWithPointers<T> = class abstract(TEnumerable<T>)
protected
  function GetPtrEnum: TEnum<PT>; virtual; abstract;
end;
TIntList = class(TWithPointers<LongInt>) end;          { unknown type: PT }
```

fpc 3.2.2 `-Mdelphi` compiles both. One instantiation is enough — the corpus's
four-way `TEnumerator$PT` collision was this defect counted again, not a
multiplicity effect.

**F is the arm that works, and WHY it works says where the fix is not.** It works
through the HOIST path: `CollectHoistCandidates` scans the template being
specialized for nested `type` declarations and re-declares each one under a name
unique to the specialization (`TWithPointers$LongInt$PT`), so the argument is a
real unit-level type by the time it is used. That path is a REWRITE, not a
lookup — which is why your v1/v2 reading ("two lookups serve one question and
only one walks the class") is the right layer and this is a third route to the
same question rather than a fourth lookup.

**I tried the obvious fix at the hoist layer and it is the wrong layer — do not
repeat it.** Extending `CollectHoistCandidates` to walk the ancestor chain
(collecting inherited nested types under the same specialization prefix) makes E
and a two-instantiation variant compile and run correctly, and on the pre-`1c16d4523`
tree it made `uses Generics.Collections` **hang** (>90s, no runaway minting —
176 mint lines and then silence) and produced `unknown type: TList$UInt32$PT`:
the hoisted NAME reaches the argument while its declaration does not reach the
scope that needs it. The patch is stashed locally in the frankS checkout only —
it is not on origin and nobody should plan on it — and its value is this
paragraph, not the diff. Whoever fixes the lookup should re-check E; it may well
fall out with v1 and needs no hoist change at all.

**Not wired `blocked-by:` on the rung**, for the reason you filed it with: the
corpus now stops earlier, at `generics.defaults.pas:3250`, on a different shape.

## 2026-09-09 (frankS) — what an unresolved `PT` does downstream, measured

Not a claim about this ticket's cause; a measurement of its consequence on the
rtl-generics rung, in case it is useful for ranking. When the bare `PT` at
generics.collections.pas:212 is carried into a specialization's name as the
still-unsubstituted parameter name, the run climbs a 55-rung ladder — 10 aliases
per rung — ending in `too many deferred specializations` only because
`MAX_SPECIALIZATIONS = 256` stops it. `p.nspec` names the pump: the seed
registers a two-argument reference with `nsub=1 subs=T->UInt32`, and each later
rung's substitution is the previous rung's alias
(`subs=T->TEnumerable$UInt32$PT` -> `subs=T->TEnumerable$TEnumerable$UInt32$PT$PT`).

**Correction to the first version of this note (`de029d555`), which I also sent
you by message:** I claimed the alias gained a `$PT` segment its `args=` did not
have. That was a substring-counting artifact — the alias spells the separator
and the argument does not. All 872 mints satisfy
`alias = tmpl + '$' + join('$', args)`. The mangler is not the site; the
arguments are what runs away.

Filed as
[[bug-p-a-specialization-alias-grows-one-segment-per-round-when-an-argument-never-resolves]]
and kept SEPARATE from this ticket deliberately: the mangler surplus is testable
on its own, and I have not shown that resolving `PT` ends the ladder. **That is
the discriminator if you want to merge the two** — resolve `PT` at :212 and see
whether the mint count drops to one rung.

## 2026-09-09 (frankZ) — TWO of the three doors are FIXED. What remains is one, and it is named

**Fixed:** every ladder row whose nested type is declared in a NON-GENERIC class
— its own (v5, v6, v8, v10, v11) or a non-generic ANCESTOR's (v3, v4) — plus the
silent arm, which now answers 300 where it answered 44. Regression test
`test/test_a_class_nested_type_is_a_specialization_argument.pas`, six rows,
byte-matching fpc 3.2.2, wired into the Makefile sweep.

**Negative control, run clean on the pre-fix binary `90aa9c2c1c10`:** `rc=1`,
five errors, no binary produced — `unknown type: TAlias`, `unknown type:
TInner`, `unknown type: TAfter` (the template body carrying the bare spellings)
and two `SizeOf: unknown type or variable`. Note which name is ABSENT from that
list: `TElem`, the `mixed` row, because the unit-scope namesake absorbed it.
**The control errors on four rows and is silent on the fifth**, which is the row
that was wrong. Only the VALUE assertion catches it, and that is why the test
reads `V` and not `SizeOf` — both compilers answer 8 for the size.

### The mechanism, no longer a hypothesis

`NestedSpecArg` (`pasparser_generic.inc:420`) maps an argument identifier
through exactly two tables: `SpecSubNames`, the enclosing template's own
parameters, and `HoistedNameFor`, the names the enclosing template declares in
its OWN body via `CollectHoistCandidates` — which stops at `depth <= 0`. A name
in neither survives into the alias as its literal spelling. That is the whole
defect, and the three doors are three ways to be in neither table:

| door | shape | table that misses | status |
| --- | --- | --- | --- |
| A | non-generic class, own or non-generic ancestor's nested type | neither — the token sweep never consults one | **fixed here** |
| B | the template's own body | `HoistedNameFor` covers it | already worked |
| C | inherited from a GENERIC ancestor | `CollectHoistCandidates` walks one body, not the chain | **open** |

Door A does not go through `p.nspec` at all — it is the token-level
`DelphiRewriteGenericUses` sweep, which minted `TEnum$PT` directly. Measuring
that is what separated the doors; a `p.nspec` probe on the ticket's own 15-line
repro prints nothing.

### The remedy, and the half that is load-bearing

Hoist the DECLARATION and leave an ALIAS behind — the same shape the
template-side door already uses, over `Tokens` instead of `TemplateTokens` and
with no substitution to apply:

```
TDerived$PT = ^Integer;                    <- lifted, above TDerived
TEnum$TDerived$PT = specialize TEnum<TDerived$PT>;
TDerived = class
  type PT = TDerived$PT;                   <- alias, NOT a second copy
  function F: TEnum$TDerived$PT;
end;
```

A top-level DUPLICATE would be structurally identical but a DISTINCT type, so
`d.P` and the specialization's result would not assign to each other. Collapsing
the in-body declaration is not an optimisation; it is the correctness half.

**Two things the first cut got wrong, both measured rather than reasoned:**

- **The method IMPLEMENTATION header is a second scope and missing it moved
  nothing.** `function TDerived.GetPtrEnum: TEnum<PT>;` sits at unit level,
  outside every class body, and Delphi resolves its signature in TDerived's
  scope. With only the body arm wired, the declaration was rewritten and the
  implementation was not, the two headers named different types, and the
  template was still minted on the bare spelling — **the symptom did not change
  at all**, which reads exactly like a fix that does nothing.
- **A qualified argument must be skipped, not rewritten.** `TEnum<TDerived.PT>`
  — the v7 row, a separate open bug — had its `PT` rewritten into
  `TDerived.TDerived$PT`, a name the source never wrote and a strictly worse
  diagnostic than the one it replaced. An ident preceded by `tkDot` now belongs
  to the qualified-argument arm and is left alone. v7 is back to its own
  original failure, unchanged.

### The closure guard, and why it fails in the safe direction

`PT = ^TDerived` lifted above `TDerived` is a forward reference we would be
creating ourselves. The RHS is refused when it names anything declared at or
after the class. The test is crude on purpose — a `const nm = 3` counts — and
the asymmetry is deliberate: a false positive costs a refused hoist, i.e. a
program exactly as broken as it already was, while a false negative would cost
a new defect.

### Door C is the remaining wall, and it is now the LAST one on the Collections driver

frankS's `2473d920e` closed the `TQueue`/`TEnumerator` cycle that made the
rtl-generics failure a ladder; what stands behind it is this ticket's plain
`unknown type: PT`. **Seventeen-line reduction, no corpus, fpc 3.2.2 accepts and
runs it:**

```pascal
program n1;
{$mode delphi}
type
  TEnumerable<T> = class
  public type
    PT = ^T;
  end;
  TPointersEnum<T, P> = class
    function G: P; virtual; abstract;
  end;
  TListWithPointers<T> = class(TEnumerable<T>)
  public
    function Ptrs: TPointersEnum<T, PT>;
  end;
function TListWithPointers<T>.Ptrs: TPointersEnum<T, PT>; begin Result := nil; end;
var a: TListWithPointers<LongInt>;
begin a := nil; WriteLn('ok'); end.
```

```
PXXDBG p.nspec reg alias=TPointersEnum$LongInt$PT under=TListWithPointers$LongInt nsub=1 subs=T->LongInt
pascal26:9: error: unknown type: PT
```

fpc's own mangled name in that program says what it resolved to:
`TPointersEnum$2<SYSTEM.LongInt,N1.TEnumerable$1$crc9F312717.PT>`.

**`nsub=1` is CORRECT and reading it as the argument count was an error that
cost a round of analysis.** The `p.nspec` probe prints `SpecSubCount` — the
substitution set in force — and `TListWithPointers<T>` has exactly one
parameter. The reference's own argument count is `na`/`NSpecNArg` and the probe
does not print it. Both arguments ARE recorded; the second simply resolves
through neither table.

**Why the ancestor extension is worth one run and not obviously doomed.** The
hoisted name for the ancestor's member under a substitution is
`TEnumerable$LongInt$PT` — the same name a specialization of `TEnumerable`
itself would mint. It is STABLE across rungs, so `HoistEmitted`, which is keyed
on the name, does its job. Bound it to the case where the ancestor's argument
list is exactly the descendant's own parameters in order (`class(TEnumerable<T>)`
inside `TListWithPointers<T>`) and the substitution carries over unchanged;
anything else is refused. That is the next thing to try and it is mine.

## 2026-09-09 (frankZ) — DOOR C: the ancestor chain, and the pre-existing defect it uncovered

`CollectHoistCandidates` is now split: `ScanTemplateBodyForHoists(ti, prefix)`
appends one body's nested types under a given top-level prefix, and
`CollectHoistCandidates` calls it for the template and then for every ANCESTOR
the template passes its parameters straight through to.

**What makes it terminate**, which is the question the earlier hang raised: the
ancestor's member is lifted to `<ancestor>$<the same argument values>$<nm>` —
exactly the name a specialization of the ancestor ITSELF would mint. It is
STABLE across rungs, so `HoistEmitted`, keyed on the name, recognises it. A
scheme whose name grew per rung would defeat that guard and re-emit forever.

**Three conditions, all required, and refusing is the safe answer to each:**

1. the ancestor's argument list is this template's parameter list verbatim —
   `class(TEnumerable<Integer>)` or a reordering binds the ancestor's
   parameters to something else;
2. the ancestor's OWN parameter names are the same names — `TEnumerable<TItem>`
   inherited as `<T>` passes (1) and its body still says `TItem`, which is not
   in `SpecSubNames`, so the hoisted RHS would come out `^TItem` and declare a
   type from a name that does not exist;
3. the ancestor must be a template we know.

A refused rung leaves the program exactly as broken as it was.

### `class abstract(...)` — a control drawn from the wrong population, and it cost a corpus run

The first cut tested the token immediately after `class` for `(`. Every
hand-written reduction passed. **The entire rtl-generics corpus failed**,
because the hint words sit BETWEEN the keyword and the parenthesis and
rtl-generics writes nearly every one of these classes as `class abstract(...)`.
Nobody puts `abstract` in a fifteen-line repro, so the repro population and the
corpus population disagree on exactly the token the walk was reading. The test
now carries both spellings on the ladder.

### The two-instantiation row is NOT in this ticket's test, and why

Extending the walk made a PRE-EXISTING defect reachable from more places, and it
is filed separately with its own 21-line repro:
`bug-p-a-hoisted-nested-type-name-leaks-between-two-specializations-of-one-template`.

`HoistName`/`HoistFull` are one global table that `CollectHoistCandidates`
resets per specialization. `NestedSpecArg` reads it eagerly and bakes the answer
into `NSpecArg`, so the answer is right for whatever the table held AT SCAN
TIME — and a method-implementation header is one token range shared by every
specialization, scanned after a later one has refilled the table. Two
specializations of `TOwner<T>` mint `TPtrs$LongInt$TOwner$Byte$PT`: LongInt's
header paired with **Byte's** hoisted PT, then `unknown type` on a name the
compiler invented itself.

**Not mine, and that was checked rather than assumed:** the repro fails
identically on `c8ba1d666f79` (`3a89c6184`), which contains door A and not
door C. **One instantiation is green**, which is why every hoisting test in
`test/` passes while the defect is live — none of them specializes a template
twice.

### Corpus state

`uses Generics.Defaults` alone is NOT this ticket. At HEAD it takes 30.8s and
fails with `unresolved forward: TInstance.CreateSelector`, the first error and
nothing before it; with door C stashed and the compiler rebuilt, 31.0s and
byte-identical text. That wall is somebody else's.

`uses Generics.Collections` before door C aborted early on `duplicate class name
TEnumerator$PT`. With the first door-C cut — the one that refused every
`class abstract` ancestor — it ran 7m17s to completion and surfaced 12 errors,
reaching generics.defaults.pas:1054 and generics.collections.pas:1354. **The
extra time is extra work, not a hang**: it no longer aborts, so it compiles the
rest of the unit.

### The corpus numbers, and a wrong one I sent a peer

| tree | outcome |
| --- | --- |
| HEAD, door A only | **ABORTS** on `duplicate class name TEnumerator$PT` — no error count exists |
| door C, first cut (no `class abstract`) | 7m17s, 12 errors, compiles end to end |
| door C with `class abstract` | 6m59s, 11 errors, compiles end to end |

**So the `class abstract` fix bought exactly one error on the corpus**, not the
transformation the reduction ladder suggested, and `unknown type: PT` at
:120/123/217 is unmoved by any of it. **Door C's value is the reduced shapes it
fixes, not the corpus.**

**I quoted "3 errors" to a peer from a log that was still being written.** The
run takes seven minutes and the first three errors land in the first seconds, so
`grep -c` mid-run returns a stable, confident, wrong total — it does not error
and nothing about it looks partial. Corrected in the same channel. The general
form is the one CLAUDE.md already names: a truncated read is an instrument that
is correct about something else, here about the first ten seconds.

### Next step, and it is one question

Which site mints `TEnumerator<PT>` with the bare spelling. `TEnumerator<PT>`
appears at generics.collections.pas:133 (inside `TEnumerable<T>`'s own body,
where `PT = ^T` is declared two lines above — door B, which works), at :144
(`TCustomPointersEnumerator<T, PT>`, where PT is that template's own PARAMETER),
at :152, and at :222/:361/:554/:619/:862 as `GetPtrEnumerator: TEnumerator<PT>;
override;` in descendants. One of them resolves `PT` to nothing. A
`PXXDBG=p.mint:TEnumerator,p.specbound` run over the corpus names it; it costs
seven minutes and nobody has spent them.

## 2026-09-09 (frankZ) — THE LADDER, RE-MEASURED AT `61a9463be` / binary `24f4fc4ec625`

Every row re-run, not copied forward. The v-numbers are the original ladder's.

| | shape | before | now |
| --- | --- | --- | --- |
| v1 | inherited nested type used PLAINLY | ok | ok |
| v2 | spec arg, GENERIC ancestor + generic descendant | unknown type: PT | **ok** |
| v3 | same, ancestor NON-generic, `PT = ^Integer` | unknown type: PT | **ok** |
| v4 | same, ancestor AND descendant non-generic | unknown type: PT | **ok** |
| v5 | no inheritance, the class declares `PT` itself | unknown type: PT | **ok** |
| v6 | `TElem = Integer`, a plain alias not a pointer | unknown type: TElem | **ok** |
| v7 | qualified: `TEnum<TDerived.TElem>` | unknown type: TDerived | unchanged — `bug-p-a-qualified-type-name-cannot-be-a-generic-argument` |
| v8 | v6 plus a unit-scope namesake declared FIRST | ok | ok |
| v9 | concrete argument (control) | ok | ok |
| v10 | v8 with the namesake a DIFFERENT type | ok, **v=44** | ok, **v=300** |
| v11 | v6 with the namesake declared AFTER the class | unknown type: TElem | **ok** |

v7 is the one row untouched and it is deliberately untouched: the qualified
argument now gets SKIPPED by the hoist rewrite rather than mangled into
`TDerived.TDerived$PT`, which returns it to its own original failure. Its alias
`$qual$TDerived$PT = TDerived.PT;` is still emitted above `TDerived`, which is
that ticket's defect and not this one's.

**What is left here is one question and it is narrow.** Of the 8 `TEnumerator`
mints the Collections driver produces at this tree, seven resolve
(`$TCustomList$UInt32$PT` x4, `$UInt32` x2, `$TEnumerable$UInt32$PT` x1) and
exactly one is bare `alias=TEnumerator$PT tmpl=TEnumerator args=PT`. It is
labelled `deferred`. `TEnumerator<PT>` is written at generics.collections.pas
:133, :144, :152, :222, :361, :554, :619 and :862; one of those eight resolves
`PT` to nothing.

**And the obvious next experiment has already been run and it settled nothing.**
The bare mint has the signature of a scan with an empty hoist table, which is
also the signature of
`bug-p-a-hoisted-nested-type-name-leaks-between-two-specializations-of-one-template`
— but fixing that one's call site made the corpus WORSE, not better, so no link
between them was established. Recorded so nobody spends the seven minutes twice.

## THE EIGHT SITES ARE NOT ONE POPULATION — TWO OF THEM SPELL `PT` AS A TEMPLATE PARAMETER (frankZ, 2026-09-09)

Read from the corpus source rather than from a probe, so this is a HYPOTHESIS
about which site mints the bare alias, not a measurement of it. What it does
settle is that the question "which of the eight" was drawn from a population
that has two different shapes in it, and only one of them is this ticket's.

**Six sites: `PT` is a NESTED TYPE.** `TEnumerable<T>` declares `PT = ^T` two
lines above its own use at :133, and the descendants at :222/:361/:554/:619/:862
inherit it. That is door B and door C, and the census says they work — the seven
resolving mints are all of this shape (`$TEnumerable$UInt32$PT`,
`$TCustomList$UInt32$PT` x4, `$UInt32` x2).

**Two sites: `PT` is a TEMPLATE PARAMETER of the enclosing template**, and
neither is a nested type at all:

```pascal
  // generics.collections.pas:144
  TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);

  // generics.collections.pas:152, inside
  TCustomPointersCollection<T, PT> = object
    function GetEnumerator: TEnumerator<PT>;
```

`:144` is a **declaration-time base-clause** prerequisite with an EMPTY class
body — `= class abstract(...)` and then a semicolon, no `end` — so the group is
scanned when `TCustomPointersEnumerator` is DECLARED, before anything specializes
it, when `SpecSubCount` is 0 and `PT` can only map to itself. That is the exact
shape that produces `args=PT`, and the bare mint is labelled `deferred`, which
is the prerequisite path and not the late one. `:152` is the same spelling
inside an `object`, not a class.

**Why this matters beyond naming a line number:** a fix aimed at the hoist
tables cannot reach either of them. `PT` there is not a name to hoist; it is a
parameter awaiting a substitution that has not been established yet. If the
measurement confirms `:144`, this ticket's remaining question belongs to
declaration-time prerequisite ordering and not to nested-type resolution, and
should be re-laned as its own ticket rather than left as the tail of this one.

**The measurement that settles it** is `PXXDBG=p.nspec:TEnumerator` over the
Collections driver, reading `nsub` and `under` on the bare row: `nsub=0` says
declaration time and names `:144`/`:152`; a non-zero `nsub` with a real `under`
says one of the six and keeps the question here. Seven minutes, not yet run.

**Unmoved by the hoist-leak fix.** `unknown type: PT` at :120/:123/:217 is
present at `00ca0d61bbce`, which carries
`bug-p-a-hoisted-nested-type-name-leaks-between-two-specializations-of-one-template`
in full. Those three rows are `TEnumerator<T>`'s own body materialised as
`TEnumerator$PT` — the alias was emitted and its `T` substituted with the
unresolved spelling — so they are the bare mint's consequence, not a separate
wall.

### The hoist-leak fix is now EXCLUDED, by a control and not by an argument

Two 7-minute Collections runs, differing by exactly the 20 lines of
`bug-p-a-hoisted-nested-type-name-leaks-between-two-specializations-of-one-template`:
`00ca0d61bbce` (with) and `68421d8ff193` (without, verified to fail that
ticket's own fixture first). **Byte-identical error lists, 14 rows each.**

So the bare `alias=TEnumerator$PT` is not the leak, and this is no longer an
experiment that settled nothing — it is a negative result with a control. The
two-population reading above is what is left, and `:144` is the candidate.

**The residual question has an owner and it is this ticket**, until the `nsub`
measurement re-lanes it.
