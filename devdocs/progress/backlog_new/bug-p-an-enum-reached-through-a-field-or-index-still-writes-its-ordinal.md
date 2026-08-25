---
slug: bug-p-an-enum-reached-through-a-field-or-index-still-writes-its-ordinal
title: "`WriteLn(a[0])` / `WriteLn(r.f)` / `WriteLn(Succ(e))` / `WriteLn(TE(1))` still print the ordinal"
track: P
prio: 40
type: bug
blocked-by: []
status: backlog_new
owner: ""
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
