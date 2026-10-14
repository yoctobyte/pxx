program test_rv32_leaf_operands_skip_the_spill;
{ riscv32 used to spill a0 to the stack around operands that cannot disturb
  it. Four shapes no longer do, and each is checked against x86-64 here:
  - a managed string stored into a frame local or a var parameter takes the
    old handle into a1, stores the new one, then releases the old -- new
    already holds its own +1, so `s := s` and friends must survive, at
    refcount 1 too: P(x, x) through var/const and var/var, and a record field
    and an array element assigned to themselves (Churn, 500 passes, under the
    leak census);
  - a string concat / compare whose operands are plain variables releases
    nothing, so the result is not pushed and popped around nothing;
  - an array index that is a constant is a byte offset folded at compile time
    (lower bounds other than 0, element sizes that are not powers of two,
    offsets past the 12-bit immediate), and a frame-local index loads straight
    into a1;
  - a store through memory of a constant, or of an integer local when nothing
    in the address can run, loads the value after the address. An address
    that CALLS something keeps pxx's order: the value is read first. }
{$mode objfpc}
uses SysUtils;
type
  TTri = packed record a, b, c: Byte; end;
  TBig = record x, y, z: LongInt; end;
  TSRec = record n: LongInt; s: AnsiString; end;
  PLongInt = ^LongInt;
var
  g: AnsiString;
  tri: array[0..9] of TTri;
  bigs: array[-3..3] of TBig;
  wide: array[5..1205] of LongInt;
  bytes: array[1..40] of Byte;
  words: array[0..7] of Word;
  cell: LongInt;
  i: LongInt;

procedure Twice(var s: AnsiString);
begin
  s := s + s;
end;

procedure Keep(var s: AnsiString);
begin
  s := s;
end;

procedure SetTo(var s: AnsiString; const v: AnsiString);
begin
  s := v;
end;

{ var/var alias: P(x, x) with x at refcount 1 -- b's handle is a plain copy,
  so it is retained before the store and x never drops to zero }
procedure CopyVar(var a, b: AnsiString);
begin
  a := b;
end;

function Bump(var x: LongInt): PLongInt;
begin
  Inc(x, 100);
  Result := @cell;
end;

procedure Strings;
var a, b, c: AnsiString; n: LongInt;
begin
  a := 'abc';
  b := a;
  a := a;
  b := b + a;
  c := b;
  c := c + c;
  writeln(a, ' ', b, ' ', c);
  Twice(a); Keep(a); writeln(a);
  SetTo(b, b); SetTo(c, a); writeln(b, ' ', c);
  n := 0;
  if a = c then Inc(n);
  if a <> b then Inc(n, 10);
  if b < a then Inc(n, 100);
  if a + 'x' = c + 'x' then Inc(n, 1000);
  writeln(n);
  for n := 1 to 50 do a := a + Chr(48 + n mod 10);
  writeln(Length(a), ' ', Copy(a, 40, 12));
end;

{ Every store-then-release shape, 500 times: a handle that is not released
  (or released twice) shows up as hundreds live in the census row, or as a
  crash, where one pass would hide in the noise. }
procedure Churn;
var a, b, x: AnsiString; k, hits: LongInt; r: TSRec; arr: array[0..2] of AnsiString;
begin
  hits := 0;
  for k := 1 to 500 do
  begin
    a := 'n' + IntToStr(k);
    b := a;
    a := a;
    Keep(a);
    SetTo(b, a);
    Twice(b);
    if b = a + a then Inc(hits);
    if a <> b then Inc(hits);
    g := b;
    { aliases at refcount 1: each x is fresh and the only reference }
    x := 'x' + IntToStr(k);
    SetTo(x, x);            { var a / const b, P(x, x) }
    CopyVar(x, x);          { var a / var b, P(x, x) }
    Keep(x);
    x := x;
    if x = 'x' + IntToStr(k) then Inc(hits);
    { the old value is the only reference to the new one: a record field and
      an array element assigned to themselves }
    r.s := 'r' + IntToStr(k);
    r.s := r.s;
    arr[k mod 3] := 'e' + IntToStr(k);
    arr[k mod 3] := arr[k mod 3];
    if (r.s = 'r' + IntToStr(k)) and (arr[k mod 3] = 'e' + IntToStr(k)) then Inc(hits);
  end;
  writeln(hits, ' ', g, ' ', x, ' ', r.s, ' ', arr[0], arr[1], arr[2]);
end;

procedure Indexes;
var k, j: LongInt; t: TTri; total: Int64;
begin
  for k := 0 to 9 do
  begin
    tri[k].a := k; tri[k].b := k * 2; tri[k].c := k * 3;
  end;
  t := tri[7];
  writeln(t.a, ' ', t.b, ' ', t.c, ' ', tri[0].c, ' ', tri[9].b);
  for k := -3 to 3 do
  begin
    bigs[k].x := k; bigs[k].y := k * k; bigs[k].z := -k;
  end;
  writeln(bigs[-3].y, ' ', bigs[3].z, ' ', bigs[0].x, ' ', bigs[-1].z);
  for k := 5 to 1205 do wide[k] := k * 3;
  writeln(wide[5], ' ', wide[517], ' ', wide[518], ' ', wide[1205]);
  for k := 1 to 40 do bytes[k] := 200 + k;
  for k := 0 to 7 do words[k] := 60000 + k;
  total := 0;
  j := 3;
  for k := 5 to 1205 do total := total + wide[k];
  writeln(total, ' ', bytes[j], ' ', bytes[40], ' ', words[j], ' ', tri[j].c, ' ', bigs[j - 3].y);
end;

procedure Stores;
var x, y: LongInt; p: PLongInt; sm: SmallInt; q: ^SmallInt;
begin
  p := @cell;
  p^ := 12345;
  writeln(cell);
  x := -7;
  p^ := x;
  writeln(cell);
  q := @sm;
  q^ := -2;
  writeln(sm);
  y := 40000;
  q^ := y;
  writeln(sm);
  { the address runs Bump, which changes x. pxx reads the value first on
    every target (1 101); FPC evaluates the address first (101 101) -- the
    order is unspecified in Pascal, so the oracle is pxx on x86-64, and this
    line pins that riscv32 keeps pxx's order here instead of reordering. }
  x := 1;
  Bump(x)^ := x;
  writeln(cell, ' ', x);
  for y := 0 to 7 do PLongInt(@wide[100 + y])^ := y * 11;
  writeln(wide[100], ' ', wide[107]);
end;

begin
  g := 'glob';
  g := g + g;
  g := g;
  writeln(g);
  Strings;
  Churn;
  Indexes;
  Stores;
  writeln('done');
end.
