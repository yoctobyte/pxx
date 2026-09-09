---
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: frankZ
summary: "A type named as a SPECIALIZATION ARGUMENT inside a class body is resolved where the class does not yet exist. Class-nested is the case it was found through and NOT the boundary — frankH's `TEnum<TDerived>` inside `TDerived` fails on the class's own unit-scope name; the boundary is \"declared at or after the class's own declaration\". `TDerived = class public type TElem = Int64; function F: TBox<TElem>; end;` refuses with `unknown type: TElem` when no unit-scope namesake exists — and when one DOES exist it silently specializes on the WRONG type: measured `v=44` where fpc prints `v=300`, a 300 stored through a unit-scope `TElem = Byte` while the source meant the nested `Int64`. A plain use of the same nested name one line away resolves correctly, so the compiler knows which type is meant and the specialization does not ask. Fourth arm of the same sentence as bug-p-a-specializations-concrete-argument-is-keyed-by-its-spelling — the mechanism is the hoisted prerequisite's INSERTION POINT, not visibility and not the routine-local pass-order arm. Eleven-row reduction ladder in the body, re-measured at compiler 417ee5636a72 / d47ae0762 AFTER 1c16d4523 landed; nothing moved, so this is not that fix's defect. NOT the rtl-generics rung's blocker: 1c16d4523 cleared `unknown type: PT` there (attributed by revert-rebuild, which attributes THAT and cannot speak to the new wall's cause) and that wall is now generics.defaults.pas:3250, owned by bug-p-a-generic-method-implementation-is-attributed-by-name-not-arity."
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
