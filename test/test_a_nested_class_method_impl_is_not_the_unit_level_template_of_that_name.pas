{ A nested class's method IMPLEMENTATION belongs to the class at the HEAD of its
  qualified path, not to a unit-level template that happens to share the LAST
  component's name.

  `constructor TQueue<T>.TEnumerator.Create` loses its `<T>` in the Delphi
  rewrite and reads `constructor TQueue . TEnumerator . Create`. Every
  `<ident> .` in that path answers a name match, so specializing the unit-level
  `TEnumerator<T>` used to scan TQueue's nested class body and mint a
  `TQueue<...>` nobody asked for. On rtl-generics that spurious edge closes a
  cycle -- TBase<X> needs TEnumerator<X.PT>, TEnumerator<Y> wrongly needs
  TQueue<Y>, TQueue<Y> needs TBase<Y> -- and the argument grows one segment per
  round until `too many deferred specializations`.

  THE SHAPE IS THE ASSERTION: without the fix this file does not produce a wrong
  number, it fails to compile at all. fpc 3.2.2 -Mdelphi accepts it.
  bug-p-a-specialization-alias-grows-one-segment-per-round-when-an-argument-never-resolves }
program test_a_nested_class_method_impl_is_not_the_unit_level_template_of_that_name;
{$mode delphi}
type
  TEnumerator<T> = class
    FV: T;
    function Cur: T;
  end;

  TBase<T> = class
  public type
    PT = ^T;
    function G: TEnumerator<PT>; virtual; abstract;
  end;

  TQueue<T> = class(TBase<T>)
  public type
    TEnumerator = class
      FQ: TQueue<T>;
      constructor Create(AQueue: TQueue<T>);
    end;
  end;

function TEnumerator<T>.Cur: T;
begin
  Result := FV;
end;

constructor TQueue<T>.TEnumerator.Create(AQueue: TQueue<T>);
begin
  FQ := AQueue;
end;

var
  e: TEnumerator<Integer>;
  b: TBase<Integer>;
begin
  e := TEnumerator<Integer>.Create;
  e.FV := 42;
  WriteLn('cur ', e.Cur);
  b := nil;
  if b = nil then WriteLn('base nil');
end.
