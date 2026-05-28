program test_ir_deref;
var
  arr: array[1..3] of Integer;
  pt: TFixup;
  i: Integer;
begin
  arr[1] := 10;
  arr[2] := 20;
  arr[3] := 30;
  pt.CodePos := 100;
  pt.DataOff := 200;
  
  i := 2;
  writeln(arr[1]); { 10 }
  writeln(arr[i]); { 20 }
  writeln(pt.CodePos); { 100 }
  writeln(pt.DataOff); { 200 }
end.
