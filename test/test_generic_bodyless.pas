program test_generic_bodyless;
{$mode objfpc}{$H+}
{ A class declaration need not HAVE a body: `= class(Parent);` is complete on
  its own. The generic-template capture counted down to a matching `end` and,
  finding none, ran on and swallowed whatever declaration ended next --
  rtl-generics' one-line
    `TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>);`
  took 126 further lines into the template with it, and the damage surfaced as
  an error deep inside the swallowed text. TAfter below is the canary: it is
  what got eaten. }
type
  generic TBox<T> = class
    V: T;
    function Get: T;
  end;
  generic TDerived<T> = class(specialize TBox<T>);
  TAfter = class
    X: Integer;
  end;

function TBox.Get: T;
begin
  Result := V;
end;

var
  d: specialize TDerived<Integer>;
  s: specialize TDerived<string>;
  a: TAfter;
begin
  d := specialize TDerived<Integer>.Create;
  d.V := 7;
  s := specialize TDerived<string>.Create;
  s.V := 'hi';
  a := TAfter.Create;
  a.X := 3;
  WriteLn('bodyless ', d.Get, ' ', s.Get, ' ', a.X);
  d.Free; s.Free; a.Free;
  WriteLn('GENERIC BODYLESS OK');
end.
