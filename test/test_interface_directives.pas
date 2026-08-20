program test_interface_directives;
{$mode objfpc}{$H+}
{ An interface method signature may carry directives: `overload`, a calling
  convention, and the hint directives. The interface member loop had no
  directive handling at all, so the parse stopped where one stood --
  rtl-generics' Generics.Defaults opens with
    `function Compare(constref Left, Right: T): Integer; overload;`.
  They are all parse-and-ignore here: an interface method is abstract and
  virtual by definition, overload resolution is signature-keyed, and pxx has
  one internal calling convention.

  Two same-named interface overloads are NOT exercised here on purpose: pxx
  picks an interface method by declaration slot, so a call selects the first
  of the name regardless of argument type. That is a separate defect (a
  silently wrong value, filed on its own); baking it into this test's expected
  output would freeze it. }
type
  IThing = interface
    function Compare(constref L, R: Integer): Integer; overload;
    function CompareStr(constref L, R: string): Integer; overload;
    procedure Poke; stdcall;
    function Legacy: string; deprecated 'use Poke';
  end;

  TThing = class(TInterfacedObject, IThing)
    function Compare(constref L, R: Integer): Integer; overload;
    function CompareStr(constref L, R: string): Integer; overload;
    procedure Poke; stdcall;
    function Legacy: string;
  end;

function TThing.Compare(constref L, R: Integer): Integer;
begin
  if L < R then Result := -1 else if L > R then Result := 1 else Result := 0;
end;

function TThing.CompareStr(constref L, R: string): Integer;
begin
  if L < R then Result := -1 else if L > R then Result := 1 else Result := 0;
end;

procedure TThing.Poke; stdcall;
begin
  WriteLn('poke');
end;

function TThing.Legacy: string;
begin
  Result := 'legacy';
end;

var
  i: IThing;
begin
  i := TThing.Create;
  WriteLn('cmp ', i.Compare(2, 5), ' ', i.CompareStr('b', 'a'));
  i.Poke;
  WriteLn('legacy ', i.Legacy);
  WriteLn('INTERFACE DIRECTIVES OK');
end.
