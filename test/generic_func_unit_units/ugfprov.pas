{ Provider half of test_generic_func_in_unit: a `generic function` DECLARED in a
  unit interface and DEFINED in the implementation. Both spellings were rejected
  outright until bug-p-a-generic-function-cannot-be-declared-in-a-unit -- the
  interface header as `expected generic class name`, the implementation
  definition as `unexpected token in a unit implementation section` -- while the
  identical declaration at PROGRAM level compiled. FPC 3.2.2 accepts both. }
unit ugfprov;
{$mode objfpc}

interface

type
  { present on purpose: `generic` opens a TYPE or a ROUTINE, and only the token
    after it says which. A generic routine declared beneath a type section used
    to reach ParseGenericTemplate and die there, so the section above is part of
    the subject and not decoration. }
  TTag = record n: Integer; end;

generic function Twice<T>(a: T): T;
generic function Bump<T>(a: T): T;
function ProviderTag: Integer;

implementation

generic function Twice<T>(a: T): T;
begin
  Result := a + a;
end;

generic function Bump<T>(a: T): T;
begin
  Result := a;
  try
    Result := a + a;
  finally
    Result := Result + 1;
  end;
end;

function ProviderTag: Integer;
begin
  Result := 7;
end;

end.
