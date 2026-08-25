---
slug: bug-p-an-enum-reached-through-a-field-or-index-still-writes-its-ordinal
title: "`WriteLn(a[0])` / `WriteLn(r.f)` / `WriteLn(Succ(e))` / `WriteLn(TE(1))` still print the ordinal"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "`WriteLn(e)` now prints the member name (FPC parity). Every OTHER way of naming the same value still prints the ordinal, because the enum identity is carried by the SYMBOL (SymEnumId) and by a folded member literal (ASTEnumId) and by nothing else — an array element, a record field, a function result, a cast and Succ/Pred all lose it. So the same enum prints two different ways in one program, which is a worse shape than the uniform wrongness it replaced."
---

# Measured, 2026-08-25 (HEAD, self-hosted fixedpoint), vs `fpc 3.2.2 -Mobjfpc -O1`

```pascal
type TE = (One, Two, Three);
var e: TE; a: array[0..1] of TE; r: record f: TE; end;
begin
  e := Three;   WriteLn(e);        { fpc: Three   pxx: Three   OK }
  a[0] := Two;  WriteLn(a[0]);     { fpc: Two     pxx: 1       }
  r.f := One;   WriteLn(r.f);      { fpc: One     pxx: 0       }
  WriteLn(Succ(One));              { fpc: Two     pxx: 1       }
  WriteLn(TE(1));                  { fpc: Two     pxx: 1       }
end.
```

# Root cause — a data-model shortfall, not a missing arm

`NodeEnumIdOf` can answer for exactly two node shapes:

- `AN_IDENT` → `SymEnumId[sym]`
- a folded enum-member literal → `ASTEnumId[node]`

There is nowhere else to ask. Grepping `defs.inc` for the concept turns up
**eight** parallel spellings — `SymEnumId`, `SymSetEnumId`, `ASTEnumId`,
`UPropEnumId`, `UPropSetEnumId`, `UFldSetEnumId`, `ProcParamSetEnumId`,
`SetConstEnumId`, plus `LastTypeEnumId`/`LastTypeSetEnumId` as the parser's
scratch — and note what is NOT among them: there is **no `UFldEnumId`** (a
record/class field's own enum type) and no element enum id for an array. A
property knows its enum type; the field under it does not.

So the microfix is "add `UFldEnumId` and `SymElemEnumId`", and that is the wrong
move: it makes ten spellings of one question. `devdocs/dev/root-cause-over-microfix.md`
— two mechanisms for one concept is a smell, three is a design flaw, and this is
eight.

# The shape of the real fix

Stamp `ASTEnumId` on **every** expression node whose static type is an enum, at
construction, and let `NodeEnumIdOf` become a single read of it. That needs the
enum id to travel with the TYPE rather than with each table that stores one,
which is exactly the consolidation
[[decide-typeref-gains-a-pointer-depth-field]] is arguing about for pointer
depth — same sprawl, same repo, one migration. Resolve that fork first, or at
least decide the enum id rides the same vehicle, before adding a ninth array.

# Why the partial state is still an improvement

The bare-variable form is overwhelmingly the common one, it was silently wrong,
and it is now right on every target (the lowering is a compare/branch chain over
IR ops every backend already handles). Measured blast radius when it landed: all
51 enum-declaring programs in `test/` produced byte-identical output before and
after, so nothing in the corpus was relying on the ordinal.

`test/test_writeln_of_an_enum_prints_its_name.pas` states this boundary in its
header and deliberately asserts none of the shapes above, so that closing this
ticket is a matter of extending that file rather than discovering what was meant.

# Resolution, 2026-08-25

All eight shapes now print the member name, matching `fpc 3.2.2 -Mobjfpc -O1`:

| shape | where the identity now lives |
| --- | --- |
| `a[i]`, `b[i]` (alias), `d[i]` (dynamic), `dd[i][j]` | `SymElemEnumId` |
| `r.f`, `c.fk`, `r.inner.k` | `UFldEnumId` |
| `r.g[i]`, `c.ka[i]` | `UFldEnumId` (an array field's slot holds the ELEMENT's enum) |
| `F` (call result) | `ProcRetEnumId` |
| `p` (`var` and by-value param) | `SymEnumId` on the param symbol |
| `K` (typed const) | `SymEnumId` on the const's symbol |
| `Succ(e)` / `Pred(e)` | `ASTEnumId`, stamped on the desugared binop |
| `TE(i)` | `ASTEnumId`, stamped on the cast node |

`NodeEnumIdOf` is the single reader and its comment is now the map.

## Why three more parallel slots, when the ticket argued against a ninth

The ticket's own analysis said "stamp `ASTEnumId` on every enum-typed expression
node at construction, and resolve
[[decide-typeref-gains-a-pointer-depth-field]] first". That is still the right
END state, and it is NOT what landed. What the analysis missed is that the
stamp has to come FROM somewhere: for `Succ`/`Pred` and a cast the parser can
derive it (those two are exactly the `ASTEnumId` arms above, and they cost
nothing), but for a field, an array element and a call result there was no
source to stamp from. The data gap was the whole bug; a node-level stamp does
not close it.

So the three slots are the missing STORAGE, not a ninth spelling of the
question. Each is the direct twin of one the codebase already had —
`UFldSetEnumId` : `UFldEnumId`, `SymSetEnumId` : `SymElemEnumId`,
`ProcParamSetEnumId` : `ProcRetEnumId` — one per ENTITY, which is how every
other type attribute in this compiler is stored today
(`SymPtrElemTk`/`UFldPtrElemTk`/`ProcRetPtrElemTk` is the same triple). They
sit alongside their siblings, so
[[feature-a-typeref-migrate-consumers]] sweeps them with the arrays they were
modelled on rather than finding a new shape. `NodeEnumIdOf`'s comment names all
four and points at that migration.

## The trap this hit twice, and the guard both times

*An array symbol's TypeKind IS its element kind* — the root cause that has now
cost six fixes in this repo. `array[0..1] of TE` therefore reaches every decl
site with `tk = tyInteger` and a live `LastTypeEnumId`, and the pre-existing code
in `pasparser_stmt.inc` was already stamping `SymEnumId` on it. That is the slot
meaning "this VALUE is an enum", so once `WriteLn` started reading it, a whole
array would have claimed to be an enum member. Both readers are guarded:

- the `AN_IDENT` arm answers nothing when `Syms[i].IsArray`;
- the `AN_FIELD` arm answers nothing when `UFldIsArray[fi]`;
- and the two `pasparser_stmt.inc` decl sites now route an array to
  `SymElemEnumId` instead of `SymEnumId`.

`ProcRetEnumId` has the same trap on the WRITE side: an array-returning function
reaches the return-type code with `retType` = the element kind and a stale
`LastTypeEnumId`, so it is explicitly forced to -1 for `retArrAi >= 0` /
`retIsDynArr`. `AddUField` never reads `LastTypeEnumId` at all — the C frontend
calls it with `tyInteger` constantly — so the Pascal field-decl sites stamp it,
mirroring how `SymEnumId` is set at var-decl sites and never inside `AllocVar`.

## Measured

- `test/test_enum_name_through_field_index_and_call.pas` — 24 rows covering every
  shape above plus the ordinal contexts (`Ord`, a `for` loop, the `:8` width
  form) that must stay numeric. Diffs MATCH against fpc 3.2.2; `.expected` IS
  fpc's own output. Wired into `test-core`.
- `test_writeln_of_an_enum_prints_its_name.pas`'s "NOT covered" paragraph updated
  — it was the note that predicted this ticket.
- fpc-testsuite, same skiplist and same command before and after: **345 pass,
  1 fail, 170 skip** both times. No movement in either direction.
  (`tdefault8.pp(compile)` fails in both runs; unrelated.)
- `make compiler/pascal26` fixedpoint converged in one round at every step;
  `tools/gate.sh quick` GREEN.

## What this surfaced

`refactor-p-the-field-declaration-parser-exists-twice` — every edit here had to
be made twice, because a record's field parser and a class's are two copies of
the same 120 lines. Filed rather than fixed: the enum work put both copies back
in step, and the lift is its own change.

Still open, and asserted around rather than to: `MkAlias[0]` (indexing an
array-returning call) is refused by
`compat-pascal-index-a-function-call-result`, so the array-alias result is
asserted through a variable.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
