program test_generic_nested_diamond;
{$mode objfpc}{$H+}
{ A DIAMOND of nested generic prerequisites: TTop needs TLeftA and TRightB,
  and both of those need TBase — with the SAME argument. Each deferral queues
  its own copy of the `TBase$Integer = specialize TBase<Integer>;` alias, so
  the second copy arrives after the first has already been declared. It is an
  exact re-statement (same template, same arguments, and the name is minted
  from exactly those), so it must be a no-op rather than a duplicate-class
  error. rtl-generics reaches TCustomComparer<string> through both
  TGStringComparer and TOrdinalComparer this way. }
type
  generic TBase<T> = class
    V: T;
    function Get: T;
  end;

  generic TLeftA<T> = class(specialize TBase<T>)
    function Left: T;
  end;

  generic TRightB<T> = class(specialize TBase<T>)
    function Right: T;
  end;

  { the diamond's apex: both prerequisites reached from one declaration }
  generic TTop<T> = class
    L: specialize TLeftA<T>;
    R: specialize TRightB<T>;
  end;

function TBase.Get: T;
begin
  Result := V;
end;

function TLeftA.Left: T;
begin
  Result := V;
end;

function TRightB.Right: T;
begin
  Result := V;
end;

var
  t: specialize TTop<Integer>;
begin
  t := specialize TTop<Integer>.Create;
  t.L := specialize TLeftA<Integer>.Create;
  t.R := specialize TRightB<Integer>.Create;
  t.L.V := 4;
  t.R.V := 9;
  WriteLn('diamond ', t.L.Left, ' ', t.R.Right, ' ', t.L.Get + t.R.Get);
  t.L.Free; t.R.Free; t.Free;
  WriteLn('GENERIC NESTED DIAMOND OK');
end.
