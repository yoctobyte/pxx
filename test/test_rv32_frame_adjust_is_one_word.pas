program test_rv32_frame_adjust_is_one_word;
{ On riscv32 --platform=esp a proc's frame adjust is ONE word: `addi sp,sp,-N`
  when the frame fits +/-2048, else a `j` to a thunk after the body that
  builds the size in t0, subtracts it and jumps back. Frames on both sides of
  2048 bytes, a large-frame proc that nothing calls placed before the live
  ones (so dead-code elimination moves the code after it), a nested proc
  with a large frame, recursion through a large frame (one level: an ESP
  main task has 8 KiB of stack), and a large-frame proc whose locals are
  written at both ends. Prints the same on x64. }
{$mode objfpc}

type
  { just past the 2048 an addi reaches, and small enough that the deepest
    chain here (two frames) stays well inside an 8 KiB ESP main task stack }
  TBig = array[0..639] of LongInt;       { 2560 bytes }
  TMid = array[0..519] of LongInt;       { 2080 bytes }

function DeadBig(k: LongInt): LongInt;
var a: TBig;
    i: LongInt;
begin
  for i := 0 to High(a) do a[i] := i * k;
  Result := a[High(a)] + a[0];
end;

function Small(a, b: LongInt): LongInt;
var t: array[0..3] of LongInt;
begin
  t[0] := a; t[3] := b;
  Result := t[0] * 10 + t[3];
end;

function Edge(k: LongInt): LongInt;
var a: array[0..508] of LongInt;        { just under 2048 with the frame }
    i: LongInt;
begin
  for i := 0 to High(a) do a[i] := i + k;
  Result := a[0] + a[High(a)];
end;

function Big(k: LongInt): LongInt;
var a: TBig;
    i, s: LongInt;
begin
  for i := 0 to High(a) do a[i] := i xor k;
  s := 0;
  for i := 0 to High(a) do s := s + a[i];
  Result := s + Small(a[0], a[High(a)]);
end;

function Outer(k: LongInt): LongInt;
var m: TMid;

  function Inner(j: LongInt): LongInt;
  var b: TMid;
      i: LongInt;
  begin
    for i := 0 to High(b) do b[i] := i + j;
    Result := b[High(b)] + m[0];
  end;

begin
  m[0] := k; m[High(m)] := -k;
  Result := Inner(k) + m[High(m)];
end;

function Deep(n: LongInt): LongInt;
var m: TMid;
begin
  m[0] := n; m[High(m)] := n * 2;
  if n = 0 then Exit(0);
  Result := m[0] + m[High(m)] + Deep(n - 1);
end;

begin
  writeln(Small(3, 4));
  writeln(Edge(5));
  writeln(Big(7));
  writeln(Outer(9));
  writeln(Deep(1));
  writeln(Big(-1), ' ', Small(Edge(1), Outer(2)));
end.
