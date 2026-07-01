program test_sizeof_array_typename;
type
  TRec  = record a, b, c: Integer; end;
  TInt  = Integer;
  TArr  = array[0..9] of Integer;
  TArrRec = array[0..4] of TRec;
  TDynArr = array of Integer;
  PI    = ^Integer;
  TEnum = (eA, eB, eC);
  TProc = procedure(x: Integer);   { collides in name-shape with the compiler's
                                      own internal TProc RTTI descriptor record
                                      -- must resolve to the user's alias, not
                                      the builtin (bug-sizeof-array-and-typename-
                                      wrong, symptom 2 shadowing landmine) }
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
  writeln(SizeOf(TInt));    { 4 }
  writeln(SizeOf(TArr));    { 40 }
  writeln(SizeOf(TArrRec)); { 60 }
  writeln(SizeOf(TDynArr)); { 8, dynamic array = handle }
  writeln(SizeOf(PI));      { 8 }
  writeln(SizeOf(TEnum));   { 4 }
  writeln(SizeOf(TProc));   { 8, not the shadowed builtin TProc record }
  writeln(SizeOf(TRec));    { 12, named record type (not just a record var) }
end.
