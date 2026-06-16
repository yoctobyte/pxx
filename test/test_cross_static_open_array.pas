program test_cross_static_open_array;

{ A STATIC (fixed-length) array passed to an `array of T` open-array parameter:
  Length() must report the real element count. Open arrays read their
  length from the dyn-array header at [data-8]; a static array has none, so the
  lowering copies it into a dyn array (with header) first. Previously Length()
  returned 0 (byte-identical-wrong) on every target. Output must be identical
  across all targets. }

procedure check(const a: array of Integer);
var i, s: Integer;
begin
  s := 0;
  for i := 0 to Length(a) - 1 do s := s + a[i];
  writeln('len=', Length(a), ' sum=', s, ' a0=', a[0]);
end;

var arr: array[0..3] of Integer;
    two: array[0..1] of Integer;
begin
  arr[0] := 10; arr[1] := 20; arr[2] := 30; arr[3] := 40;
  two[0] := 7; two[1] := 8;
  check(arr);
  check(two);
end.
