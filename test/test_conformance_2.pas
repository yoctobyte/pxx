program test_conformance_2;

{ Cross-portable conformance harness (feature-synthetic-feature-matrix-test).
  Uses only the language surface that ALL backends support today — no classes,
  no Double function results, no variants — so it must produce byte-identical
  output on x86-64, i386, ARM32 and AArch64 (diffed against the x86-64 oracle).
  Densely mixes Int64, frozen strings, records (incl. >8 bytes and managed
  fields), dynamic arrays, array of const, open arrays, recursion, mutual
  recursion, many-arg calls, large frames, case and exceptions. }

type
  TRec = record
    A: Int64;
    B: Integer;
    Name: AnsiString;
  end;
  PInt64 = ^Int64;

{ --- Int64 by-value and by-ref, mixed with 32-bit operands --- }
procedure I64Bump(var x: Int64; by: Integer);
begin
  x := x + Int64(by) * 1000000000;
end;

function I64Mix(a: Int64; b: Integer): Int64;
begin
  I64Mix := (a shl 4) + Int64(b) - (a div 7) + (a mod 5);
end;

{ --- record by value > 8 bytes with a managed field --- }
function RecSum(const r: TRec): Int64;
begin
  RecSum := r.A + Int64(r.B);
end;

procedure DescribeRec(const r: TRec);
begin
  writeln('  rec ', r.Name, ' A=', r.A, ' B=', r.B, ' sum=', RecSum(r));
end;

{ --- recursion + mutual recursion --- }
function Fact(n: Integer): Int64;
begin
  if n <= 1 then Fact := 1 else Fact := Int64(n) * Fact(n - 1);
end;

function IsEven(n: Integer): Boolean; forward;
function IsOdd(n: Integer): Boolean;
begin
  if n = 0 then IsOdd := False else IsOdd := IsEven(n - 1);
end;
function IsEven(n: Integer): Boolean;
begin
  if n = 0 then IsEven := True else IsEven := IsOdd(n - 1);
end;

{ --- many args (stack-arg ABI boundary) --- }
function Sum9(a, b, c, d, e, f, g, h, i: Integer): Integer;
begin
  Sum9 := a + b + c + d + e + f + g + h + i;
end;

{ --- large frame (forces big stack offsets / frame-encode paths) --- }
function BigFrame(seed: Integer): Integer;
var buf: array[0..2047] of Integer; i, s: Integer;
begin
  for i := 0 to 2047 do buf[i] := (i + seed) mod 97;
  s := 0;
  for i := 0 to 2047 do s := s + buf[i];
  BigFrame := s;
end;

{ --- open array (array of T) by const --- }
function OpenSum(const a: array of Int64): Int64;
var i: Integer; acc: Int64;
begin
  acc := 0;
  for i := 0 to High(a) do acc := acc + a[i];
  OpenSum := acc;
end;

{ --- array of const --- }
procedure DumpVarRec(const items: array of const);
var i: Integer; p: PChar;
begin
  for i := 0 to Length(items) - 1 do
  begin
    if items[i].VType = vtInteger then writeln('  i ', items[i].VInteger)
    else if items[i].VType = vtInt64 then writeln('  q ', PInt64(items[i].VInt64)^)
    else if items[i].VType = vtBoolean then writeln('  b ', items[i].VBoolean)
    else if items[i].VType = vtAnsiString then
    begin
      p := PChar(items[i].VAnsiString); write('  s ');
      while p^ <> Chr(0) do begin write(p^); p := PChar(Pointer(p) + 1); end;
      writeln;
    end
    else writeln('  ? ', items[i].VType);
  end;
end;

{ --- exceptions: raise <integer> with try/finally/except + reraise (the
  cross-portable form; class-based except needs class instantiation, absent on
  some targets) --- }
procedure Boom(code: Integer);
begin
  raise code;
end;

function GuardedDiv(a, b: Integer): Integer;
begin
  try
    if b = 0 then Boom(1);
    GuardedDiv := a div b;
  except
    GuardedDiv := -1;
  end;
end;

var
  q: Int64;
  r: TRec;
  recs: array of TRec;
  fixed: array[0..3] of Int64;
  i: Integer;
  caught: Integer;
  s: AnsiString;

begin
  { Int64 mixed arithmetic }
  q := 5;
  I64Bump(q, 7);
  writeln('q=', q, ' mix=', I64Mix(q, 3));
  writeln('fact20=', Fact(20));

  { mutual recursion }
  writeln('even10=', IsEven(10), ' odd7=', IsOdd(7));

  { many args + large frame }
  writeln('sum9=', Sum9(1, 2, 3, 4, 5, 6, 7, 8, 9), ' big=', BigFrame(3));

  { records: dynamic array of record with managed field }
  SetLength(recs, 3);
  for i := 0 to 2 do
  begin
    recs[i].A := Int64(i + 1) * 1000000000;
    recs[i].B := i * i;
    recs[i].Name := 'r';
  end;
  for i := 0 to High(recs) do DescribeRec(recs[i]);

  { whole-record copy + by-value pass }
  r := recs[2];
  r.B := 99;
  writeln('copy A=', r.A, ' B=', r.B, ' orig B=', recs[2].B);

  { open array over a fixed array of Int64 }
  fixed[0] := 10; fixed[1] := 20; fixed[2] := 30; fixed[3] := 40;
  writeln('opensum=', OpenSum(fixed));

  { array of const mixing types }
  DumpVarRec([42, Int64(9000000000), True, 'mixed']);

  { string concat + index + case }
  s := 'abc';
  s := s + 'def';
  writeln('concat=', s, ' len=', Length(s));
  for i := 1 to Length(s) do
    case s[i] of
      'a', 'e': write('V');
      'c', 'd': write('-');
    else write('.');
    end;
  writeln;

  { exceptions: nested try/finally inside try/except, plus a guarded helper }
  caught := 0;
  try
    try
      Boom(5);
    finally
      caught := caught + 10;
    end;
  except
    caught := caught + 1;
  end;
  writeln('caught=', caught, ' gdiv=', GuardedDiv(20, 4), ' gzero=', GuardedDiv(20, 0));
end.
