---
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: frankZ
summary: "A class-nested type used as a SPECIALIZATION ARGUMENT is resolved at UNIT scope, not in the class that declares it. `TDerived = class public type TElem = Int64; function F: TBox<TElem>; end;` refuses with `unknown type: TElem` when no unit-scope namesake exists — and when one DOES exist it silently specializes on the WRONG type: measured `v=44` where fpc prints `v=300`, a 300 stored through a unit-scope `TElem = Byte` while the source meant the nested `Int64`. A plain use of the same nested name one line away resolves correctly, so the compiler knows which type is meant and the specialization does not ask. Fourth arm of the same sentence as bug-p-a-specializations-concrete-argument-is-keyed-by-its-spelling — the mechanism is class-nested visibility at the hoisted prerequisite, not the routine-local pass-order arm. Nine-row reduction ladder in the body, re-measured at compiler 417ee5636a72 / d47ae0762 AFTER 1c16d4523 landed; nothing moved, so this is not that fix's defect. NOT the rtl-generics rung's blocker: 1c16d4523 cleared `unknown type: PT` there (attributed by revert-rebuild) and that wall is now generics.defaults.pas:3250."
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

## THE LADDER — nine variants, all re-measured at `1c16d4523` / binary `417ee5636a72`

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

**NOT MEASURED, and it is the half a fix turns on:** whether the prerequisite is
hoisted ahead of the CLASS (so the nested type genuinely does not exist yet in
token order) or merely parsed with the class scope switched off (so the row
exists and the filter hides it). v4 is consistent with both — its `TBase` is
fully closed before `TDerived`, and the nested type is still not found. Settle
that before designing anything: the first reading needs the nested type hoisted
too and drags its whole dependency graph along, and the second needs an owner
column on the NSpec row and a scope window while those tokens are read. **They
are not the same size of change.** `PXXDBG=p.specsplice` (frankH, `1c16d4523`)
is the channel that separates them and it is already in the tree.

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
