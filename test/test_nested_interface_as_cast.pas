program test_nested_interface_as_cast;
{ Regression: a nested interface-to-interface `as`-cast `(x as IC) as IA` must
  work. The inner as-cast lowers to the ADDRESS of its fat-pointer temp; the outer
  cast's trap read that address as the instance and Halt-1'd on a valid cast.
  See bug-pascal-nested-interface-as-cast. }
type
  IA = interface ['{aaaaaaaa-0000-0000-0000-000000000001}'] function Ga: longint; end;
  IC = interface ['{cccccccc-0000-0000-0000-000000000003}'] function Gc: longint; end;
  TLeaf = class(TInterfacedObject, IA, IC)
    fl: longint;
    function Ga: longint;
    function Gc: longint;
  end;
function TLeaf.Ga: longint; begin Ga := fl + 1; end;
function TLeaf.Gc: longint; begin Gc := fl + 3; end;
var a: IA; o: TLeaf;
begin
  o := TLeaf.Create; o.fl := 100;
  a := o;
  writeln('inline=', ((a as IC) as IA).Ga);   { 101 }
  a := nil;
end.
