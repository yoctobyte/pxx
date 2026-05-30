program test_record_copy;
{ Whole-record assignment must copy the full record, not a hardcoded 8 bytes.
  Previously records larger than 8 bytes were truncated (only the first qword
  moved) — both ident:=ident and arr[i]:=arr[j]. Fixed via IR_COPY_REC (rep
  movsb of RecSize). }
type
  TBig = record A, B, C, D: Integer; end;   { 16 bytes }
var
  x, y: TBig;
  arr: array[0..3] of TBig;
  i: Integer;
begin
  y.A := 1; y.B := 2; y.C := 3; y.D := 4;
  x := y;                       { ident := ident }
  writeln(x.A, ' ', x.B, ' ', x.C, ' ', x.D);     { 1 2 3 4 }
  for i := 0 to 3 do
  begin
    arr[i].A := i * 10; arr[i].B := i * 10 + 1;
    arr[i].C := i * 10 + 2; arr[i].D := i * 10 + 3;
  end;
  arr[0] := arr[2];             { arr[i] := arr[j] }
  writeln(arr[0].A, ' ', arr[0].B, ' ', arr[0].C, ' ', arr[0].D);  { 20 21 22 23 }
end.
