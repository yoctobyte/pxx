program test_packed_array_field_b258;
{ `packed` is legal on an ARRAY, not just on a record — `entries: packed array[0..0] of
  TRec` (fcl-fpcunit's testutils). The field/var type parsers only knew `packed record`,
  so `packed array` fell through to ParseTypeKind, whose tkPacked case assumes a record
  and demanded one ("Expected: record, but got: array").

  `packed` on an array affects ELEMENT padding only, and pxx already lays array elements
  out contiguously, so it is accepted and the array parsed exactly as an unpacked one. }
type
  TItem = packed record
    a: Integer;
    b: Integer;
  end;

  TRec = record
    n: Integer;
    arr: packed array[0..3] of Integer;
    items: packed array[0..1] of TItem;
  end;

var
  r: TRec;
  v: packed array[0..2] of Integer;     { and at the var position }
begin
  r.n := 1;
  r.arr[2] := 7;
  r.items[1].b := 9;
  v[0] := 5;
  writeln('sum=', r.n + r.arr[2] + r.items[1].b + v[0]);
  writeln('elems=', r.arr[2], ' ', r.items[1].b);
end.
