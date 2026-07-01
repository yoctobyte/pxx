program test_nested_dynarray_setlen;
{ Nested dynamic arrays (array of array of T) on cross targets, compiled with
  -dPXX_MANAGED_STRING. bug-nested-dynarray-cross-segfault: per-row
  SetLength(a[i], n) on a depth-2 array segfaulted on arm32/aarch64 and gave no
  output on i386 -- root cause was IR_LEA for a dynamic-array symbol always
  loading the handle regardless of write/read mode on those three backends
  (x86-64 already gated this on InLValueWrite), so SetLength on the array
  itself (the outer level, or the root symbol of a nested SetLength(a[i], n))
  silently wrote through the CURRENT handle value instead of the slot.
  Output is identical on every target (oracle pattern). }

type TIntArr = array of Integer;

var
  a: array of array of Integer;
  g: TIntArr;
  i, j: Integer;

procedure ByRefResize(var arr: TIntArr; n: Integer);
begin
  SetLength(arr, n);
end;

function LocalArraySum: Integer;
var loc: TIntArr; k: Integer;
begin
  SetLength(loc, 3);
  for k := 0 to 2 do loc[k] := k * k;
  Result := loc[0] + loc[1] + loc[2];
end;

begin
  { Per-row SetLength on a depth-2 array (the original repro). }
  SetLength(a, 2);
  for i := 0 to 1 do SetLength(a[i], 3);
  for i := 0 to 1 do
    for j := 0 to 2 do
      a[i][j] := i * 10 + j;
  writeln(Length(a), ' ', Length(a[0]), ' ', a[1][2]);   { 2 3 12 }

  { Plain depth-1 global array: index-write must still see the array's own
    data pointer, not the slot address (the regression the first fix attempt
    introduced and this test catches). }
  SetLength(g, 3);
  for i := 0 to 2 do g[i] := i + 10;
  writeln(Length(g), ' ', g[0], ' ', g[1], ' ', g[2]);   { 3 10 11 12 }

  { SetLength through a var-param (by-ref) named dynamic-array type. }
  ByRefResize(g, 5);
  writeln(Length(g));                                    { 5 }
  g[4] := 99;
  writeln(g[4]);                                          { 99 }

  { SetLength + index-write on a routine-local (non-global) dynamic array. }
  writeln(LocalArraySum);                                 { 5 }
end.
