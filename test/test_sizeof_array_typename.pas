program test_sizeof_array_typename;
type
  TRec = record a, b, c: Integer; end;
var
  arr10: array[0..9] of integer;
  arr3:  array[1..3] of integer;
  bytes: array[0..15] of byte;
  recs:  array[0..4] of TRec;
  m:     array[0..2,0..2] of integer;
  r:     TRec;
begin
  writeln(SizeOf(arr10));   { 40 }
  writeln(SizeOf(arr3));    { 12 }
  writeln(SizeOf(bytes));   { 16 }
  writeln(SizeOf(recs));    { 60 }
  writeln(SizeOf(m));       { 36 }
  writeln(SizeOf(r));       { 12, unchanged control case }
end.
