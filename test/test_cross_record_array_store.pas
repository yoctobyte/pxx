program test_cross_record_array_store;

{ Regression guard for the (now non-reproducible) "whole-record array-element
  copy in the main-program body emits store no-ops" bug. A direct
  `arr[i] := someRecord` over a multi-field record (including a managed string
  field) must round-trip every field without the historical field-by-field
  workaround. Output is identical on every target as on x86-64. }

type
  TItem = record
    name: string;
    a: Integer;
    b: Integer;
    c: Integer;
  end;

var
  arr: array[0..3] of TItem;
  r: TItem;
  i: Integer;
begin
  for i := 0 to 3 do
  begin
    r.name := 'item';
    r.a := i;
    r.b := i * 10;
    r.c := i * 100;
    arr[i] := r;          { whole-record array-element store in main body }
  end;
  for i := 0 to 3 do
    writeln(arr[i].name, ' ', arr[i].a, ' ', arr[i].b, ' ', arr[i].c);
end.
