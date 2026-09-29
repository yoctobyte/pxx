program test_setlength_on_a_string_n_clamps_at_n;
{ SetLength on a string[N] clamps the count at N, in every shape: a variable, a
  record field, an array element and a `p^`. A negative count gives 0, and a
  HexStr/OctStr/BinStr width past 255 gives 255 characters.

  THIS IS A DELIBERATE DIVERGENCE FROM fpc, and the expected output is pxx's.
  fpc 3.2.2 clamps only at 255: SetLength on a string[10] to 50 reads back 50
  and a fill overruns the variable (its output shows the neighbour's bytes).
  pxx chooses memory safety over matching an overrun. fpc also takes a width
  constant of 300 as a byte (44). The rows fpc defines are in
  test_setlength_on_a_shortstring_clamps_at_255, against fpc's own output.
  No uses clause, so the frozen (-uPXX_MANAGED_STRING) row can build it.
  bug-a-setlength-on-a-shortstring-does-not-clamp-at-its-capacity }
type
  TRec = record a: string[8]; g: Integer; end;
  S8 = string[8];
  PS8 = ^S8;
var
  t: string[10];
  guard: Integer;
  r: TRec;
  arr: array[0..1] of string[6];
  p: PS8;
  s: ShortString;
  n, i: Integer;
begin
  guard := 777;
  r.g := 555;
  arr[1] := 'keep';
  n := 50;
  SetLength(t, n);
  for i := 1 to Length(t) do t[i] := 'x';
  writeln('var ', Length(t), ' ', t, ' ', guard);
  SetLength(t, 50);
  writeln('literal ', Length(t));
  SetLength(r.a, n);
  for i := 1 to Length(r.a) do r.a[i] := 'f';
  writeln('field ', Length(r.a), ' ', r.a, ' ', r.g);
  SetLength(arr[0], n);
  for i := 1 to Length(arr[0]) do arr[0][i] := 'e';
  writeln('elem ', Length(arr[0]), ' ', arr[0], ' ', arr[1]);
  New(p);
  SetLength(p^, n);
  for i := 1 to Length(p^) do p^[i] := 'd';
  writeln('deref ', Length(p^), ' ', p^);
  Dispose(p);
  n := -5;
  SetLength(t, n);
  writeln('negative ', Length(t));
  SetLength(s, -1);
  writeln('negative literal ', Length(s));
  s := HexStr(1, 300);
  writeln('hexstr ', Length(s));
  s := OctStr(1, 300);
  writeln('octstr ', Length(s));
  s := BinStr(1, 300);
  writeln('binstr ', Length(s));
  writeln('guard ', guard);
end.
