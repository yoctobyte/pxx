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
  n:     array[0..1,0..2,0..4] of integer;
  mr:    array[0..1,0..2] of TRec;
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

  { SizeOf(arr[i]): the index expression is never evaluated (just its
    balanced brackets skipped), result is the element size -- lets the
    common SizeOf(arr) div SizeOf(arr[0]) element-count idiom work. }
  writeln(SizeOf(arr10[0]));                    { 4 }
  writeln(SizeOf(arr10) div SizeOf(arr10[0]));  { 10 }
  writeln(SizeOf(bytes[0]));                    { 1 }
  writeln(SizeOf(recs[0]));                     { 12, record element }
  writeln(SizeOf(recs) div SizeOf(recs[0]));    { 5 }
  writeln(SizeOf(arr10[arr10[0] + 1]));         { 4, index expression itself untouched/unevaluated }

  { SizeOf(m[i]) / SizeOf(m[i,j,..]) on a genuine N-D fixed array: a single
    leading subscript names a whole row (sub-array); one subscript per
    dimension names the scalar element -- mirrors the two subscript forms
    real N-D indexing itself supports. }
  writeln(SizeOf(m[0]));       { row: 3 ints = 12 }
  writeln(SizeOf(m[0,0]));     { scalar: 4 }
  writeln(SizeOf(n));          { 2*3*5*4 = 120 }
  writeln(SizeOf(n[0]));       { row: 3*5*4 = 60 }
  writeln(SizeOf(n[0,0,0]));   { scalar: 4 }
  writeln(SizeOf(mr[0]));      { row: 3*12 = 36 }
  writeln(SizeOf(mr[0,0]));    { scalar: 12 }
end.
