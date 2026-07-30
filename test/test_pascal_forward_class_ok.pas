{ A FORWARD stub is not a duplicate: the full declaration must fill THAT row.
  Companion to test_pascal_duplicate_class_fail.pas. }
program test_pascal_forward_class_ok;
type
  TBar = class;
  TBaz = class
    p: TBar;
  end;
  TBar = class
    n: Integer;
  end;
var b: TBar; z: TBaz;
begin
  b := TBar.Create;
  b.n := 7;
  z := TBaz.Create;
  z.p := b;
  WriteLn(z.p.n);
end.
