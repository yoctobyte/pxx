program test_setlength_clamps_with_no_builtin_in_the_program;
{ The SetLength clamp must not depend on the builtin unit being loaded. The
  first fix clamped a VARIABLE count through a builtin helper and silently
  skipped the clamp when the helper wasn't visible, and a program with no uses
  clause loads builtin only when a trigger name (HexStr, StringOfChar, ...)
  appears. The earlier fixtures called HexStr, so they passed while this
  program segfaulted (frankd-90's measurement).

  DO NOT ADD A BUILTIN CALL TO THIS FILE: no HexStr, OctStr, BinStr,
  StringOfChar, IntToHex, and no uses clause. Every count here is a variable
  or a call, never a literal, because a literal is folded at compile time and
  would pass without the runtime clamp. Each fill runs to Length and checks a
  guard. Expected output is pxx's: the ShortString rows are what fpc 3.2.2
  prints, and the string[N] and negative rows are the recorded divergence
  (pascal-dialect-divergences.md).
  bug-a-setlength-on-a-shortstring-does-not-clamp-at-its-capacity }
type
  TRec = record a: string[8]; g: Integer; end;
  PShort = ^ShortString;
var
  t: string[10];
  guard: Integer;
  s: ShortString;
  r: TRec;
  arr: array[0..1] of string[6];
  p: PShort;
  n, i, calls: Integer;

function Count: Integer;
begin
  Inc(calls);
  Result := 400;
end;

procedure ByVar(var x: ShortString);
begin
  SetLength(x, n);
  for i := 1 to Length(x) do x[i] := 'v';
  writeln('byvar ', Length(x));
end;

begin
  guard := 777;
  r.g := 555;
  arr[1] := 'keep';
  n := 50;
  SetLength(t, n);
  for i := 1 to Length(t) do t[i] := 'x';
  writeln('var ', Length(t), ' ', t, ' ', guard);
  n := 1000;
  SetLength(s, n);
  for i := 1 to Length(s) do s[i] := 'y';
  writeln('short ', Length(s), ' ', guard);
  n := -5;
  SetLength(t, n);
  writeln('negative ', Length(t));
  SetLength(s, n);
  writeln('negative short ', Length(s));
  n := 50;
  SetLength(r.a, n);
  for i := 1 to Length(r.a) do r.a[i] := 'f';
  writeln('field ', Length(r.a), ' ', r.a, ' ', r.g);
  SetLength(arr[0], n);
  for i := 1 to Length(arr[0]) do arr[0][i] := 'e';
  writeln('elem ', Length(arr[0]), ' ', arr[0], ' ', arr[1]);
  New(p);
  n := 300;
  SetLength(p^, n);
  for i := 1 to Length(p^) do p^[i] := 'd';
  writeln('deref ', Length(p^));
  Dispose(p);
  calls := 0;
  SetLength(s, Count);
  writeln('once ', Length(s), ' ', calls);
  n := 3000;
  ByVar(s);
  n := 7;
  SetLength(t, n);
  writeln('fits ', Length(t));
  writeln('guard ', guard);
end.
