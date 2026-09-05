---
slug: bug-p-a-qualified-nested-alias-is-invisible-to-low-high-and-a-constructor
track: P
prio: 30
type: bug
status: backlog
blocked-by: []
created: 2026-09-06
found-by: frankB (ctor site, predicted from mechanism); frankD (Low/High)
owner: ""
---

# `Low`, `High` and a constructor cannot see a qualified nested ALIAS, while the declaration of the same name compiles

**PRE-EXISTING, NOT FALLOUT FROM THE ALIAS-SCOPING WORK.** Say this first because a
reader meeting "qualified nested type refused" next to `c01eb17a8` and
`regression-test-core-test-record-nested-type-section` will assume those caused it.
`stable_linux_amd64/default/pinned` (symlink dated 2026-08-29, predating the entire
`AliasOwnerCi` column) refuses it with the byte-identical error.

## The finding

The DECLARATION path and the CONSTRUCTION path answer "what may follow `TOuter.`"
from two different tables, and the qualified construction walk consults only one.

```pascal
type
  TThing = class v: Integer; constructor Create; end;
  TOuter = class type TP = TThing; end;   { alias, in a class body, to a class }
var o: TOuter.TP;          { compiles }
begin
  o := TOuter.TP.Create;   { pascal26: error: class method not found (TP) }
```

Same qualifier, same alias, same owner, one line apart.

## Matrix — pxx HEAD vs fpc 3.2.2, four spellings

| | spelling | pxx | fpc |
| --- | --- | --- | --- |
| A | nested **class** ctor through owner, `TOuter.TInner.Create` | `v=1` | `v=1` |
| B | **alias**-to-class ctor through owner, `TOuter.TP.Create` | **refused** | `v=2` |
| C | same alias, ctor through the target, `TThing.Create` | `v=3` | `v=3` |
| D | **unit-level** alias to a class, `TQ.Create` | `v=4` | `v=4` |

**Row D is the row that names the defect.** The constructor path is not
alias-blind — an unqualified alias to a class constructs fine, on HEAD and on the
pin. It is specifically the *qualified* walk that cannot see an alias. So this is
not "the ctor path has never heard of aliases"; it is that its qualified walk
resolves each hop through `FindNestedType` alone, while the declaration path
(`ParseTypeKindInner`) tries `FindNestedType` **and** the alias table.

## `Low` and `High` are the same defect and are the cheaper repro

Found while re-verifying the alias-scoping fix on a rebased tree, by widening a
probe rather than by reading code:

```pascal
type TTest = class type TRange = 0..10; end;
WriteLn(Ord(Low(TTest.TRange)), ' ', Ord(High(TTest.TRange)));

  fpc 3.2.2 : 0 10
  pxx HEAD  : pascal26:4: error: class method not found (TRange)
  pxx PIN   : pascal26:4: error: class method not found (TRange)   <- pre-existing
```

**Same error string as the constructor case**, which is the tell that they are one
defect: an intrinsic that does not resolve `TOwner.TMember` through the alias table
falls through to the class-method path, and the diagnostic comes from there. `Low`
and `High` never learned the strip at all.

Note what this does to the sibling count. `Default()` and `SizeOf()` DID have the
strip and were repaired by
`regression-test-core-test-record-nested-type-section`; `Low`, `High` and the
constructor did not. So the family is **five intrinsics, two of which knew about
qualified nested types and three of which never did** — and the three that never
did agree with each other perfectly, which is exactly why reading them against
each other finds nothing.

## Where

`compiler/pasparser_expr.inc:7830` — the `TOuter.TInner.Create` arm. Both its
entry gate and its hop loop are `FindNestedType(...) >= 0`, which matches only a
nested class or record; an alias returns -1, the arm is skipped, and the flat
`IsClassType(name)` path below sees `TOuter` rather than `TP`.

Note for whoever takes it: adding `QualTypeOwnerCi` here would be a copy that
cannot fire. The alias-visibility rule is not what is missing — the alias-table
LOOKUP is. Resolving a hop needs to fall back to the alias table and then require
the target to be a class before accepting `Create`.

## How it was found

Predicted from a mechanism before it was looked for. frankB, auditing the
qualifier-strip sites while reviewing the alias-scoping regression, argued that a
rule spelled per call site fails by an ABSENT copy — invisible precisely because
the copies that exist agree with each other — and named the un-audited fourth
site. This is that site. It turned out not to be an absent copy of that rule, but
the prediction found the hole.

**The residual that makes it worth ranking above a curiosity:** two tables
answering one question is the shape that predicts a fifth site. Anywhere a
qualified `A.B` run is walked, ask which table each hop is resolved through.
