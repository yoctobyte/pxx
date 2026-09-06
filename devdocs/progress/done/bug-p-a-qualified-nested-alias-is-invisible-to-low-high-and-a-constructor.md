---
slug: bug-p-a-qualified-nested-alias-is-invisible-to-low-high-and-a-constructor
track: P
prio: 30
type: bug
status: done
blocked-by: []
created: 2026-09-06
found-by: frankB (ctor site, predicted from mechanism); frankD (Low/High)
owner: frankB
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

**Same error string as the constructor case — and that is NOT evidence they are one
defect.** Corrected here by frankB before any work started, and the correction is
load-bearing for whoever fixes this.

`class method not found` comes from the class-method path, which is where
*anything* unresolved lands. One diagnostic across three sites is exactly as
consistent with **three separate fall-throughs to a common handler** as with one
cause. All three of my readings were taken at the error-reporting layer, which is
downstream of wherever each site actually gives up — so they corroborate each
other only about the last thing that happened to them, not about why.

**Establish where each one gives up before assuming a shared fix.** They may share
one; the observation above does not show it. `Low`/`High` may not even consult the
alias table for a reason different from the constructor's `FindNestedType` gate.

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

## OWNER SET BY frankD ON frankB'S EXPLICIT REQUEST, 2026-09-06

frankB asked for it in a message, having agreed to take the row and then found it
**could not claim it: the ticket was filed after its last pull, and it cannot pull
because an `-i test-core` run is reading its sources.** Recording a claim a session
stated is attribution, not dispatch — this seat set the field, frankB owns the row.

frankB has `Low`/`High` loaded from `557d06627` (the ordinal-identity work:
`TrySetTypeBound`, `TryConstHighLowValue`, `TryFoldHighLowType`), which is the
reason it is cheaper there than here.


## RESOLVED 2026-09-06 — and the central question came back NO

**They were not one defect.** The ticket asked for where each site gives up to be
established before a shared fix was assumed. It was, by experiment:

1. `EatQualifiedTypePrefix` (new, `pasparser_class.inc`) landed first and was
   wired into `TryConstHighLowValue` / `TryFoldHighLowType` only. Measured
   immediately after: `Low(TTest.TRange)` answered **1**, and
   `TTest.TP.Make` still answered **`class method not found (TP)`**, byte for
   byte the same message as before.
2. So the bounds half and the constructor half share the *emitter* and nothing
   else. `ErrorRecover('class method not found')` is where anything unresolved
   lands; a refusal names the position and never the reason.

The bounds sites never STRIPPED the qualifier at all. The two constructor sites
stripped it correctly and then asked the wrong table. Different failures, one
message. Had one patch fixed all three, that would not have been evidence they
were one defect either — the asymmetry is not in the fix count.

### The constructor half is TWO sites, not one, and the ticket named only one

`pasparser_expr.inc:7855` (`.Create`) was in the ticket. `pasparser_lval.inc`'s
nested-scope walk — the **named**-constructor spelling, `TTest.TP.Make` — was
not, and it is a separate `while … FindNestedType(ci, fieldName) >= 0` loop in a
different file. Both now call `FindNestedClassLikeCi`.

### THE TABLE THE TICKET NAMED IS NOT THE TABLE THE ROW IS IN

The "Where" note said to fall back to *the alias table*. The first
implementation did exactly that — `AliasTk`, `AliasElemRec`, `REC_UCLASS_BASE` —
built cleanly, self-hosted, and **resolved nothing**, because
`type TP = TThing` where TThing is a class never reaches `RegisterGeneralAlias`
at all: `ParseTypeSection`'s `IsClassType` arm routes it to
`RegisterUClassAlias`, a THIRD table (`UClsAlias*`, three columns, no owner).

Every field name in the wrong version was real and every fact checked about it
was true. What was never checked was **which registrar the declaration actually
reached**. Reading `RegisterGeneralAlias`'s two call sites is what created the
confidence — a census of the function I had already decided on. The measurement
that broke it was a dump of the whole alias table: fourteen rows, all builtins,
no `TP`. **Ask which registrar ran, not which columns look like they would hold
the answer.**

So the family is not two tables answering "what may follow `TOuter.`" — it is
**three**, and the ticket's residual ("two tables is the shape that predicts a
fifth site") was right about the shape and short by a table.

### Scoping, stated rather than assumed

`FindNestedClassLikeCi`'s alias lookup is **not** owner-scoped, because the
declaration path is not either: measured, `var x: TOther.TP` compiles today for
a `TP` declared in `TTest`'s body, since `UClsAlias*` has no owner column. The
construction path now matches that exactly and is no looser. Scoping both is a
separate change with a new column in it.

### Landed

- `compiler/symtab.inc` — `FindUClassAliasCi`, extracted from `FindUClass`'s own
  tail so there is one loop, not two.
- `compiler/pasparser_class.inc` — `EatQualifiedTypePrefix` (bounds half),
  `FindNestedClassLikeCi` (constructor half).
- `compiler/pasparser_lval.inc` — `TryConstHighLowValue` / `TryFoldHighLowType`
  split into wrapper + `…Inner` so `QualTypeOwnerCi` is restored across nine
  exit points and any tenth added later; the named-ctor walk taught the alias.
- `compiler/pasparser_expr.inc` — the `.Create` walk taught the alias, and it now
  carries the RESOLVED class's own name past the walk instead of the spelling
  that named it (the `IsClassType(name)` gate below refused `TP`).
- `test/test_a_qualified_nested_alias_is_a_type_and_a_scope.{pas,expected}` —
  fpc 3.2.2 oracle, byte-identical, wired in the Makefile. Rows A–D are the
  controls and were green before the fix.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 5840f4a69.
