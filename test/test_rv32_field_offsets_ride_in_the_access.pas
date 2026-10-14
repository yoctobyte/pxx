{ riscv32: a load or store through a record field at a constant offset carries
  the offset in the lw/sw itself, and a var param's (or dynamic array's) slot
  word is one lw off(s0). Every access width, signed and unsigned, through a
  var param, a pointer, a class and a global; offsets at and past the 12-bit
  immediate (2044 keeps both words of a 64-bit access in reach, 2046 does
  not); folded constants stored through a field. Output must match x86-64. }
program test_rv32_field_offsets_ride_in_the_access;

{$mode objfpc}

const
  K = 3 * 7 + 1;

type
  TSmall = record
    b: ShortInt; ub: Byte; h: SmallInt; uh: Word;
    i: Integer; u: LongWord; q: Int64; d: Double; p: Pointer; s: AnsiString;
  end;
  PSmall = ^TSmall;
  TBig = record
    pad: array[0..2039] of Byte;
    q2044: Int64;            { 2040, both words in reach }
    pad2: array[0..1] of Byte;
    w: SmallInt;             { 2050, past imm12 }
    i: Integer;
    q: Int64;
  end;
  TObj = class
    a: Integer;
    b: Byte;
    q: Int64;
  end;
  TIntArr = array of Integer;

var
  g: TSmall;
  gb: TBig;

procedure Fill(var r: TSmall; n: Integer);
begin
  r.b := -n; r.ub := 200 + n; r.h := -1000 * n; r.uh := 60000 + n;
  r.i := -100000 * n; r.u := $F0000000 + LongWord(n); r.q := -(Int64(1) shl 40) * n;
  r.d := 1.5 * n; r.p := @r; r.s := 'n' + Chr(Ord('0') + n);
end;

function Sum(const r: TSmall): Int64;
begin
  Result := r.b + r.ub + r.h + r.uh + r.i + Int64(r.u) + r.q + Trunc(r.d) + Length(r.s);
end;

procedure Through(p: PSmall);
begin
  p^.i := p^.i + K;
  p^.h := K * 2 - 50;
  p^.q := p^.q + K;
end;

procedure BigSet(var r: TBig; v: Integer);
begin
  r.q2044 := Int64(v) * 1000000007;
  r.w := -v;
  r.i := v * 3;
  r.q := -Int64(v) shl 33;
end;

procedure Grow(var a: TIntArr; var n: Integer);
begin
  SetLength(a, Length(a) + 1);
  a[High(a)] := n;
  n := n + Length(a);
end;

var
  l: TSmall;
  o: TObj;
  a: TIntArr;
  n, j: Integer;
begin
  Fill(g, 3); Fill(l, 5);
  WriteLn(g.b, ' ', g.ub, ' ', g.h, ' ', g.uh, ' ', g.i, ' ', g.u, ' ', g.q, ' ', g.s);
  WriteLn(Sum(g), ' ', Sum(l), ' ', g.p = @g, ' ', l.p = @l);
  Through(@g); Through(@l);
  WriteLn(g.i, ' ', g.h, ' ', g.q, ' ', l.i, ' ', l.q);
  BigSet(gb, 7);
  WriteLn(gb.q2044, ' ', gb.w, ' ', gb.i, ' ', gb.q);
  o := TObj.Create;
  o.a := K; o.b := 255; o.q := Int64(K) shl 35;
  o.a := o.a + o.b;
  WriteLn(o.a, ' ', o.b, ' ', o.q);
  o.Free;
  n := 1;
  for j := 1 to 4 do Grow(a, n);
  WriteLn(Length(a), ' ', a[0], ' ', a[3], ' ', n);
end.
