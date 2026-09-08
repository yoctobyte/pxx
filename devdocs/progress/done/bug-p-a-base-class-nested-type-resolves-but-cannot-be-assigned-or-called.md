---
track: P
prio: 60
type: bug
status: done
blocked-by: []
owner: frankS
summary: "CORRECTED 2026-09-07 AND FIXED. The report said the TYPE resolved and only its procedural SIGNATURE failed to travel; measured, the type itself does not travel: `FAmt: TAmt` in a derived class body and `var q: TDer.TAmt` both answer `unknown type` at HEAD and identically on pin v407, for a plain ALIAS and a SUBRANGE as well as for the procedural type the report used. Cause: AliasVisibleHere's ParsingClassBodyCi arm walked UClsEnclosingCi (lexical) and its QualTypeOwnerCi arm did not walk at all, while only the MethImplOwnerCi arm walked UClsParent. All three inheritance arms walk now; the lexical arm is untouched. THE REASON THE OLD CLAIM SURVIVED IS THE FINDING: Alias* holds only three of the seven nested kinds -- a nested RECORD and CLASS are registry rows that FindNestedType has always walked, and a nested ENUM has no owner column at all -- so the three kinds a reader probes with are the three that never touch the table under test. Fixture test/test_a_base_class_nested_type_is_visible_to_its_derived_class.pas, 15 rows, all against fpc 3.2.2, kind named on every row for exactly that reason."
---

# A base class's nested type resolves but cannot be assigned or called

## Repro

```pascal
program r;
{$mode delphi}
type
  TBase = class
  public type
    TSel = function(a: Integer): Integer of object;
  end;
  TDer = class(TBase)
    FSel: TSel;                     { resolves -- the type name is found }
    function Twice(a: Integer): Integer;
  end;
function TDer.Twice(a: Integer): Integer;
begin Twice := a * 2; end;
var d: TDer; q: TDer.TSel;
begin
  d := TDer.Create;
  d.FSel := d.Twice;                { A: refused, "wrong number of parameters" }
  q := d.Twice;                     { assigns fine }
  WriteLn(q(21));                   { B: refused, "expected ')' before '('" }
end.
```

fpc 3.2.2 compiles and runs both. pxx refuses A, and with A removed refuses B.

## What the pair tells you

| spelling | type resolves | assign | call |
| --- | --- | --- | --- |
| local in a derived METHOD BODY (`var s: TSel`) | yes | yes | yes |
| field of the derived class (`FSel: TSel`) | yes | **no** | — |
| qualified `TDer.TSel` | yes | yes | **no** |
| the same two against the OWNING class (`TC.TSel`) | yes | yes | yes |

**The type name is never the problem** — every row resolves it. What does not
travel along the inheritance path is the alias's **procedural signature**
(`AliasProcSig`), which is what tells the parser that `d.Twice` in that position
is a method REFERENCE rather than a call, and that `q(21)` is a call rather than
a parenthesised expression. Row 1 works because the method-implementation scope
now walks `UClsParent`; rows 2 and 3 reach the alias by other paths that do not.

## Do not reuse the method-pointer framing

The sibling fix's test carries a plain `TAmt = Integer` row precisely because a
procedural-only test reads as a method-pointer bug. Here the procedural-ness IS
the subject — but check an ordinal row before assuming any fix generalises, and
check the owning-class spellings as the control that must stay green.

## Not a regression

Both rows fail identically on pin v407 (`095ef4811a5b`). Long-standing.

# CORRECTED AND FIXED — 2026-09-07 (frankS)

**The table above is wrong in its first column and the correction is the whole
finding.** It says the type resolves in every row and only `AliasProcSig` fails
to travel. Measured at HEAD and, identically, on pin v407:

| spelling | kind | type resolves |
| --- | --- | --- |
| `FAmt: TAmt` in the derived body | plain alias | **no — `unknown type`** |
| `FRng: TRng` in the derived body | subrange | **no** |
| `FSel: TSel` in the derived body | procedural | **no** |
| `q: TDer.TAmt` | plain alias | **no** |
| `q: TDer.TSel` | procedural | **no** |
| `FEn: TEn`, `q: TDer.TEn` | enum | yes |
| `FRec: TRec`, `q: TDer.TRec` | record | yes |
| `FIn: TIn`, `q: TDer.TIn` | class | yes |

So this was never a signature-propagation defect. `wrong number of parameters in
call to TDer.Twice` was the SECOND error in the file; the first was
`unknown type: TSel` on the declaration two lines up, and the assignment failed
because the field had no type, not because it had one with no signature.

## Why the original reading is a class and not a slip

`AliasVisibleHere` holds **three of the seven nested kinds**. A nested RECORD and
a nested CLASS are UClass registry rows and `FindNestedType` has walked
`UClsParent` since it was written; a nested ENUM lives in `EnumType*`, which has
no owner column, so it was never scoped at all. **The three kinds anybody reaches
for when probing "can a derived class see a base's nested type" are exactly the
three that do not exercise this table.** Three of six passing reads as "already
resolved", and the comment in `AliasVisibleHere` said so in writing — a claim
this ticket's own author then had to work around.

A probe that does not name its KIND is answering about a different table more
often than not. The fixture names the kind on every row.

## The fix

`compiler/symtab.inc`, `AliasVisibleHere`: the `ParsingClassBodyCi` arm gains an
`AliasOwnsThroughInherit` disjunct beside its existing lexical one, and the
`QualTypeOwnerCi` arm becomes `AliasOwnsThroughInherit` instead of an exact
comparison. frankB's recorded reason for keeping the qualifier arm exact is
about walking the ENCLOSING chain from a qualifier and is untouched: walking
`UClsParent` from `QualTypeOwnerCi` answers precisely the question `TDer.TAmt`
asks and cannot reach a class `TDer` does not descend from.

The stale sentence in `AliasOwnsThroughInherit`'s own header is replaced rather
than trimmed, for the reason `FindTypeAlias`'s header gives one screen up: a
stale invariant is what the next reader builds on.

## Measured and NOT fixed

`var q: TDer.TArr` — a nested named ARRAY in a qualified declaration — is still
refused. **Not this defect:** `var b: TBase.TArr` is refused identically, so
inheritance has nothing to do with it. Filed separately as
`bug-p-a-nested-array-type-is-refused-in-a-qualified-declaration`. The
unqualified body spelling `FArr: TArr` is in the fixture and passes, which is
what separates them.

Also seen and left alone: in `{$mode delphi}`, `@procvar` on an uninitialised
method-pointer global answers a non-nil address here where fpc answers the
variable's (nil) VALUE. A different subject — `@` on a procedural variable —
and no row in this fixture depends on it.

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 24ea941a1.
