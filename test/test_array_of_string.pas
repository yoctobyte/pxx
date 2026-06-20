program test_array_of_string;
{ Regression for bug-string-type-size-mismatch (per-use fix): a bare `string`
  used as an aggregate element (array/dynarray) is promoted to managed AnsiString
  in managed mode, so `array of string` works. Scalar `string` stays frozen. }
type TLB = class
  FItems: array of string;
  FCount: Integer;
end;
var a: array of string; lb: TLB; i: Integer; s: string;
begin
  SetLength(a, 3);
  a[0] := 'Apple'; a[1] := 'Banana'; a[2] := 'Cherry';
  for i := 0 to 2 do writeln(a[i]);
  lb := TLB.Create;
  SetLength(lb.FItems, 2);
  lb.FItems[0] := 'x'; lb.FItems[1] := 'yy';
  lb.FCount := 2;
  writeln(lb.FItems[0], '|', lb.FItems[1], '|', lb.FCount);
  s := 'scalar';        { scalar stays frozen, still works }
  writeln(s);
end.
