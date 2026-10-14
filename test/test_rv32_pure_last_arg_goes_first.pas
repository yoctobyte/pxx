program test_rv32_pure_last_arg_goes_first;
{ On riscv32 a call whose arguments are constants and frame locals followed
  by ONE last word that only loads and computes (a field, an element, a sum)
  evaluates that last one first, into its register, and loads the others
  after, with no push and pop of each. Leaves of every kind (constant, local,
  var argument), the last argument reading the same locals, and the 8-register
  edge. Prints the same on x64. }
{$mode objfpc}
type
  PNode = ^TNode;
  TNode = record
    len: LongInt;
    next: PNode;
    vals: array[0..3] of LongInt;
  end;

function Two(a, b: LongInt): LongInt;
begin
  Result := a * 1000 + b;
end;

function Three(a: LongInt; var c: LongInt; b: LongInt): LongInt;
begin
  c := c + 1;
  Result := a * 100 + b + c;
end;

function Eight(a, b, c, d, e, f, g, h: LongInt): LongInt;
begin
  Result := a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h;
end;

function Seven(a, b, c, d, e, f, g: LongInt): LongInt;
begin
  Result := a - b + c - d + e - f + g;
end;

procedure Run;
var
  n1, n2: TNode;
  p: PNode;
  x, y, cnt, i: LongInt;
  arr: array[0..7] of LongInt;
begin
  n1.len := 11; n1.next := @n2; n2.len := 22; n2.next := nil;
  for i := 0 to 3 do begin n1.vals[i] := i * 3; n2.vals[i] := i * 5; end;
  for i := 0 to 7 do arr[i] := i * i;
  p := @n1;
  x := 7; y := -3; cnt := 0;
  writeln(Two(x, p^.len));
  writeln(Two(5, p^.next^.len));
  writeln(Two(y, x + y * 2));
  writeln(Two(x, arr[x]));
  writeln(Two(-1, p^.vals[2] + p^.next^.vals[3]));
  writeln(Three(x, cnt, p^.len), ' ', cnt);
  writeln(Three(y, cnt, arr[cnt + 1]), ' ', cnt);
  writeln(Seven(1, x, y, 4, cnt, 6, p^.next^.len));
  writeln(Eight(1, 2, 3, x, y, 6, 7, arr[3]));
  for i := 0 to 3 do
    write(Two(i, p^.vals[i]), ' ');
  writeln;
end;

begin
  Run;
end.
