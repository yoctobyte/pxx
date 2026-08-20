---
track: P
prio: 60
---

# A method of a NESTED type cannot be implemented: `TOuter.TInner.Method`

- **Type:** feature (compat — FPC/Delphi nested types)
- **Track:** P — Pascal frontend — tag: compat
- **Status:** backlog
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
