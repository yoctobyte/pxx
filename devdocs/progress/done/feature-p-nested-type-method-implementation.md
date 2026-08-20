---
track: P
prio: 60
---

# A method of a NESTED type cannot be implemented: `TOuter.TInner.Method`

- **Type:** feature (compat — FPC/Delphi nested types)
- **Track:** P — Pascal frontend — tag: compat
- **Status:** done
- **Found:** 2026-08-20 (frank1-ACP), wall 22 of [[feature-pascal-corpus-generics]]
  (`generics.defaults.pas:2179`).

## Repro

```pascal
program r;
{$mode delphi}{$H+}
type
  TOuter = class
  public
  type
    TInstance = record
      Flag: Boolean;
      Data: Pointer;
      class function Make(AFlag: Boolean): TOuter.TInstance; static;
      function Describe: string;
    end;
  end;

class function TOuter.TInstance.Make(AFlag: Boolean): TOuter.TInstance;
begin
  Result.Flag := AFlag;
  Result.Data := nil;
end;

function TOuter.TInstance.Describe: string;
begin
  if Flag then Result := 'yes' else Result := 'no';
end;

var i: TOuter.TInstance;
begin
  i := TOuter.TInstance.Make(True);
  WriteLn('nested ', i.Describe);
end.
```

fpc 3.2.2 prints `nested yes`. pxx:

```
pascal26:15: error: unexpected token
  near:  class function TOuter  TInstance >>>  Make
```

The *declaration* side parses — the error is only on the implementation header.
The `class function ... static` form and the plain method form fail alike, so
the gap is the two-level qualification, not the `class`/`static` prefix.

## What rtl-generics needs

```pascal
class function TComparerService.TInstance.Create(ASelector: Boolean;
  AInstance: Pointer): TComparerService.TInstance;
```

plus `TComparerService.TInstance` as a var/field/array-element type and
`TInstance.Create(...)` called unqualified from inside `TComparerService`'s own
methods (`generics.defaults.pas:2381-2389`).

## Where to look

The method-implementation header parser reads `Name . Name` as
class-name/method-name. It needs to accept a dotted *type path* of any depth,
resolve all but the last component as a type, and bind the last as the method —
and the same path resolution belongs wherever a type name is read, not a second
copy in the header parser (`normalise-dont-special-case`).

## Gate

`make compiler/pascal26` + the repro above + `tools/gate.sh quick`. Add the
repro as `test/test_nested_type_methods.pas`.

## Log
- 2026-08-20 — resolved, commit 791c33fb6.

## Resolved — 2026-08-20 (frank1-ACP)

The header parser was NOT the problem: `TOuter.TInner.Method` headers already
parsed for a nested CLASS. The record arm of the type-section parser was the
gap — it called `AddUClass` directly and never `AddNestedType`, so a nested
RECORD was registered flat under its bare name and `FindNestedType` could not
see it. Class, record and interface now share one registrar,
`AddClassLikeType` (`compiler/parser.inc`), which does the enclosing-class
scoping and the nested-type registration for all three. Classic
`normalise-dont-special-case`: the class arm had been fixed by
`bug-a-duplicate-class-name-check-is-scope-blind` and the sibling arms left
behind.

The ticket's own repro was still wrong after that, for an unrelated reason found
by the new regression: a record's `class function ... static` invoked on the
TYPE name returned garbage — the arm claiming `TRec.Something(...)` was written
for a record CONSTRUCTOR (allocate a temp receiver, type the call `tyRecord`,
yield the temp) and had been taught the no-receiver shape only for a TYPE
HELPER, keyed on helper-ness instead of on `static`. Discriminator changed to
`UMthIsStatic`. This one was never about nesting at all —
`TRec.MakeI(5)` in a plain program returned garbage too, with no diagnostic.

Regressions: `test/test_nested_type_methods.pas` (nested record AND nested
class, both method-implementation forms) and
`test/test_record_static_method.pas` (ctor shape, static returning a scalar,
static returning the record). Both verified against fpc 3.2.2.
