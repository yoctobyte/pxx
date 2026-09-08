---
slug: bug-p-a-nested-array-type-is-refused-in-a-qualified-declaration
title: "`var a: TOwn.TPArr` is refused for a nested ARRAY type, while `var a: TPArr` and `var r: TOwn.TPRec` both work"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-07
summary: "FIXED 2026-09-08. Five probe sites read `CurTok.SVal` and hand it straight to `FindArrayType` BEFORE the tokens ever reach `ParseTypeKind` -- and for `TOwn.TPArr` that token is the OWNER, so every one of them missed. Each then fell through and ParseTypeKind (which strips for itself) resolved the declaration to the ELEMENT scalar: a var section, a routine-local, a class var, a record FIELD, an array ELEMENT, a value/var/open parameter and a function RESULT. The ticket's own localisation -- the ARRAY arm of ParseTypeKindInner -- points one level too deep and is wrong: ParseTypeKind is the one thing on this path that was never handed an unqualified name. The record FIELD row is the one worth reading twice: `h.f[1] := 8` INDEXED correctly through the lvalue path while `SizeOf(the record)` answered 4 against fpc's 16, so the write went past the record and nothing said so -- the arm that looked healthiest was the only one corrupting memory. Fix is one `EatQualifiedTypePrefix` ahead of each probe; the table gains no owner column, as this ticket instructed. 15 rows against fpc 3.2.2 in test_a_qualified_nested_array_type_in_a_declaration.pas."
---

# Repro

```pascal
program g1; {$mode objfpc}{$H+}
type
  TOwn = class
  type
    TPArr = array[0..3] of LongInt;
    TPRec = record a, b: LongInt; end;
  end;
var a: TOwn.TPArr; r: TOwn.TPRec;
begin
  a[0] := 42; r.a := 7;
  WriteLn('arr = ', a[0], ' rec = ', r.a, ' size = ', SizeOf(a));
end.
```

fpc 3.2.2: `arr = 42 rec = 7 size = 16`.
pxx: `pascal26:10: error: this value cannot be indexed — only arrays, strings and
pointers can (a)`, twice.

# What already works, which is the whole localisation

| spelling | pxx |
| --- | --- |
| `var a: TPArr` (bare, from outside the class) | works, indexes, right size |
| `var r: TOwn.TPRec` | works |
| `TOwn.TPArr(raw)[0]` — the qualified CAST | works (closed 2026-09-07) |
| `var a: TOwn.TPArr` | declaration accepted, value not an array |

The declaration does not FAIL, it under-resolves: no diagnostic at the
declaration, and the error arrives at the first `[`. That is the shape a
fallthrough-to-a-default produces, not a refusal.

# Where to look, and the trap next door

`EatQualifiedTypePrefix` is not the suspect — it is shared with the record
spelling above, which is right. The suspect is what `ParseTypeKindInner` does
with the stripped name in its ARRAY arm.

**Do not "fix" it by making the array lookup owner-scoped.** `ArrType*` carries
no owner column at all (nor does `EnumType*`), which is precisely why the
qualified CAST had to answer those two kinds unscoped — see
`ClassDeclaresTypeNamed`'s header and
`bug-p-a-nested-type-can-be-declared-through-a-qualifier-but-not-cast-through-one`.
Adding the column is a separate change and would want both tables at once.


# Fix (2026-09-08, frankS)

**The localisation above is wrong, and the way it is wrong is worth keeping.**
`ParseTypeKind` calls `EatQualifiedTypePrefix` internally, so it is the ONE
routine on this path that never sees a qualifier. What sees one is every probe
that runs *before* it — and there are five, each spelled by hand at its own
caller:

| site | position | before |
| --- | --- | --- |
| `pasparser_decl.inc` `ParseDeclTypeDesc` head | `var` / `class var` section | refused at the first `[` |
| same routine, dyn-element probe | `array of TOwn.TDyn` | dynamic dimension dropped |
| same routine, fixed-element probe | `array[0..1] of TOwn.TDyn` | same |
| `pasparser_decl.inc` `ParseFieldDeclInto` | record / class FIELD | **indexed fine, sized 4 instead of 16** |
| `pasparser_proc.inc` `ParseSubroutine` (x2) | value/var and open-array param | refused in the body |
| `pasparser_decl.inc` `ParseFuncReturnTypeShape` | function RESULT | refused on `Result[..]` |

The record-field row is the one that mattered. It was written into the fixture
as a CONTROL — "this spelling already works" — because `h.f[1] := 8` reads and
writes the right slot. `SizeOf(THolder)` says 4 where fpc says 16: the field was
laid out as a bare `LongInt` and the assignment wrote three LongInts past the
end of the record. **A row that passes its value assertion while the layout
under it is wrong is exactly the shape "match the assertion class to the defect
class" names**, and it survived because the lvalue path resolves the index
independently of the field's recorded size. It only appeared because the fixture
asserted a SizeOf RELATION beside the value.

`EatQualifiedTypePrefix` is the right instrument at each site and needs no guard:
it consumes nothing and returns False unless `NestedOwnerCi(name) >= 0` and a
`. ident` follows, so an unqualified or unit-qualified name is untouched — which
is what lets the strip sit ahead of the `tkArray` fork in
`ParseFuncReturnTypeShape` and cover both of that routine's probes at once. It
sets `QualTypeOwnerCi` without restoring it, deliberately, and that is the
channel the later `ParseTypeKind` lookup wants anyway.

**No owner column was added to `ArrType*` or `EnumType*`**, as this ticket
instructed. It is not needed for this: the lookup stays unscoped and the CALLER
stops handing it the wrong name.

## What was measured NOT to be this bug

- **Enum and set through the same qualifier** (`var e: TOwn.TE`, `s: TOwn.TSet`)
  were correct before and after. They reach `ParseTypeKind` with no pre-probe in
  front of them. Both are in the fixture as controls.
- **`Length`/`High` of an open-array parameter whose element is a named fixed
  row answers 0/-1** when a static-outer array is passed (`var a: array[0..2] of
  TRow; P(a)`). **The UNQUALIFIED spelling does exactly the same** — measured on
  the pristine tree, both before and after this change — so it is not this
  defect. It is the residual `done/bug-pascal-openarray-of-array-param-marshal`
  parked by name: *"static-outer P(garr) copy-in (NDims=2 guard)"*. The LITERAL
  call form `P([r0, r1])` answers 2 for both spellings and is what the fixture
  uses.
- **`SizeOf(<a function call>)`** is `SizeOf: unknown type or variable` for a
  plain top-level array type too. Separate gap, not filed — it costs one row in
  any fixture that wants it.

## Verification

`test/test_a_qualified_nested_array_type_in_a_declaration.pas`, wired into
`test-core`: 15 rows, byte-identical to fpc 3.2.2. Sizes are asserted as
RELATIONS (`SizeOf(g) div SizeOf(LongInt)`), never as byte counts, so no row
carries a target-specific constant. Positive control on the pristine tree at
`0015a3a314d1`: twelve `cannot be indexed` errors and no binary.
