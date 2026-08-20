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

  Same-named interface OVERLOADS are the second half of this test, and they
  used to be deliberately absent: the IMT builder bound every slot of a name to
  the class's FIRST method of that name (a plain FindUMeth), so `Compare(L, R)`
  and `Compare(L, M, R)` both dispatched to whichever came first and the extra
  argument was read as garbage. Silent, and only THROUGH the interface -- the
  direct class call resolved correctly the whole time
  (bug-p-interface-method-overload-picks-the-first-slot). The class below
  declares its overloads in a DIFFERENT order from the interface on purpose: a
  slot binds by SIGNATURE, so declaration position must not matter. }
type
  IThing = interface
    function Compare(constref L, R: Integer): Integer; overload;
    function Compare(constref L, R: string): Integer; overload;
    function Compare(constref L, M, R: Integer): Integer; overload;
    procedure Poke; stdcall;
    function Legacy: string; deprecated 'use Poke';
  end;

  TThing = class(TInterfacedObject, IThing)
    function Compare(constref L, M, R: Integer): Integer; overload;
    function Compare(constref L, R: string): Integer; overload;
    function Compare(constref L, R: Integer): Integer; overload;
    procedure Poke; stdcall;
    function Legacy: string;
  end;

function TThing.Compare(constref L, R: Integer): Integer;
begin
  if L < R then Result := -1 else if L > R then Result := 1 else Result := 0;
end;

function TThing.Compare(constref L, R: string): Integer;
begin
  if L < R then Result := -1 else if L > R then Result := 1 else Result := 0;
end;

function TThing.Compare(constref L, M, R: Integer): Integer;
begin
  Result := L + M + R;
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
  t: TThing;
begin
  t := TThing.Create;
  i := t;
  { through the interface -- the path that was wrong }
  WriteLn('cmp ', i.Compare(2, 5), ' ', i.Compare('b', 'a'), ' ', i.Compare(1, 2, 3));
  { ...and directly on the class, which always worked. Identical answers. }
  WriteLn('cls ', t.Compare(2, 5), ' ', t.Compare('b', 'a'), ' ', t.Compare(1, 2, 3));
  i.Poke;
  WriteLn('legacy ', i.Legacy);
  WriteLn('INTERFACE DIRECTIVES OK');
end.
