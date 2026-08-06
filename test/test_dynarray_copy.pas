{ Generic dynamic-array Copy(arr, index [, count]) -> fresh array of T. Element
  type/size come from the source symbol, so it works for any element type (here
  Integer and a 24-byte record), which a non-generic RTL routine cannot express.
  Index is 0-based (FPC dynamic-array Copy). String Copy stays the RTL path.
  Closes the dynarray part of feature-copy-intrinsic. }
program test_dynarray_copy;

type
  TP = record x, y, z: Int64; end;

var
  a, b: array of Integer;
  ra, rb: array of TP;
  i, j: Integer;

begin
  SetLength(a, 6);
  for i := 0 to 5 do a[i] := (i + 1) * 10;     { 10 20 30 40 50 60 }

  b := Copy(a, 2, 3);                           { 30 40 50 }
  Writeln(Length(b));                           { 3 }
  for i := 0 to Length(b) - 1 do Writeln(b[i]);

  b := Copy(a, 4);                              { 2-arg: 50 60 }
  Writeln(Length(b));                           { 2 }
  for i := 0 to Length(b) - 1 do Writeln(b[i]);

  b := Copy(a, 4, 100);                         { clamp to bounds }
  Writeln(Length(b));                           { 2 }

  Writeln(a[2], ' ', a[5]);                     { source intact: 30 60 }

  { record (24-byte) elements }
  SetLength(ra, 5);
  for i := 0 to 4 do begin ra[i].x := i; ra[i].y := i * 10; ra[i].z := i * 100; end;
  rb := Copy(ra, 1, 3);
  Writeln(Length(rb));                          { 3 }
  for i := 0 to Length(rb) - 1 do
    Writeln(rb[i].x, ' ', rb[i].y, ' ', rb[i].z);

  { reuse in a loop must not crash or corrupt }
  for j := 1 to 200 do b := Copy(a, 0, 6);
  Writeln(Length(b), ' ', b[5]);                { 6 60 }

  { ONE-ARGUMENT form: FPC's whole-array shorthand, Copy(a) = Copy(a, 0, Length(a)).
    This is the escape hatch that matters once assignment aliases — `b := a` shares
    the handle, `b := Copy(a)` is how you ask for a duplicate — so the independence
    check below is the point of the test, not the length
    (bug-p-copy-single-argument-form-missing-for-dynamic-arrays). }
  b := Copy(a);
  Writeln(Length(b), ' ', b[0], ' ', b[5]);     { 6 10 60 }
  b[0] := 999;                                  { must NOT reach `a` }
  Writeln(a[0], ' ', b[0]);                     { 10 999 }

  { …and for a 24-byte record element type, where the length must be scaled by
    the element size rather than assumed to be 8. }
  rb := Copy(ra);
  Writeln(Length(rb), ' ', rb[4].z);            { 5 400 }
  rb[0].x := 777;
  Writeln(ra[0].x, ' ', rb[0].x);               { 0 777 }

  { an EMPTY dynamic array — the shorthand's count comes from Length(), so a nil
    handle must give a length-0 result rather than reading the header of nil }
  SetLength(a, 0);
  b := Copy(a);
  Writeln(Length(b));                           { 0 }
end.
