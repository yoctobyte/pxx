program test_o3_resident_inplace;
uses SysUtils;
{ W2 in-place-ALU stress: every shape the pass claims, at every width, with the
  narrowing and sign-extension that the dual-write must preserve. }

procedure Widths;
var b: Byte; sb: ShortInt; w: Word; sw: SmallInt;
    c: Cardinal; l: LongInt; q: QWord; i: Int64;
    k: LongInt;
begin
  b := 250; sb := 120; w := 65000; sw := 32000;
  c := 4294967000; l := 2147483000; q := 0; i := 0;
  { in-place add with a constant, driven past each type's wrap point }
  for k := 1 to 20 do
  begin
    b := b + 1; sb := sb + 1; w := w + 100; sw := sw + 100;
    c := c + 100; l := l + 100; q := q + 3; i := i - 7;
  end;
  WriteLn('W b=', b, ' sb=', sb, ' w=', w, ' sw=', sw);
  WriteLn('W c=', c, ' l=', l, ' q=', q, ' i=', i);
end;

procedure AllOps;
var a, x, y: LongInt; k: LongInt;
begin
  a := 0; x := 12345; y := 6789;
  for k := 1 to 1000 do
  begin
    a := a + x;      { in-place add, resident right }
    a := a - y;      { NON-commutative: must be a-y, not y-a }
    a := a xor k;
    a := a and $00FFFFFF;
    a := a or 1;
  end;
  WriteLn('A a=', a);
end;

procedure SelfAndConst;
var s, k: LongInt; u: Cardinal;
begin
  s := 1; u := 1;
  for k := 1 to 30 do
  begin
    s := s + s;           { destination is ALSO the right operand }
    u := u xor u;         { must be 0, not a doubled value }
    u := u + Cardinal(k);
  end;
  WriteLn('S s=', s, ' u=', u);
end;

{$Q+}
procedure Checked;
var n, k: LongInt; ovf: Boolean;
begin
  n := 0; ovf := False;
  try
    for k := 1 to 40 do n := n + 100000000;
  except
    on E: Exception do ovf := True;
  end;
  WriteLn('Q ovf=', ovf, ' n<>0=', n <> 0);
end;
{$Q-}

procedure InTry;
var t, k: LongInt;
begin
  t := 0;
  for k := 1 to 50 do
  begin
    try
      t := t + k;
      if k = 25 then raise Exception.Create('mid');
      t := t + 1000;
    except
      on E: Exception do t := t - 7;
    end;
  end;
  WriteLn('T t=', t);
end;

procedure ByRef(var acc: LongInt; n: LongInt);
var k: LongInt;
begin
  for k := 1 to n do acc := acc + k;   { destination is a var param }
end;

procedure Params(p, r: LongInt);
var k: LongInt;
begin
  for k := 1 to 100 do
  begin
    p := p + r;      { destination is a VALUE param -- resident-eligible }
    r := r xor k;
  end;
  WriteLn('P p=', p, ' r=', r);
end;

procedure Ptrs;
var arr: array[0..9] of LongInt; p: ^LongInt; k, sum: LongInt;
begin
  for k := 0 to 9 do arr[k] := k * k;
  p := @arr[0]; sum := 0;
  for k := 0 to 9 do
  begin
    sum := sum + p^;
    p := Pointer(PtrUInt(p) + SizeOf(LongInt));   { in-place pointer add }
  end;
  WriteLn('R sum=', sum);
end;


procedure Deep(n: LongInt);
begin
  if n = 0 then raise Exception.Create('deep');
  Deep(n - 1);
end;

procedure RaisesThrough;
{ Residents in a body with NO try/except of its own, which a CALLEE unwinds
  through. The exception-frame gate does not exclude this body, so if unwinding
  reads a resident's frame slot, only this shape can show it. }
var a, b, k: LongInt;
begin
  a := 0; b := 1;
  for k := 1 to 200 do
  begin
    a := a + k;
    b := b xor a;
  end;
  try
    Deep(5);
  except
    on E: Exception do ;
  end;
  WriteLn('U a=', a, ' b=', b);
end;

procedure Through;
{ The frame that is unwound THROUGH: residents live across a raising call and
  must survive it. Its own body has no exception frame. }
var s, k: LongInt;
begin
  s := 0;
  for k := 1 to 100 do s := s + k * 2;
  Deep(3);
  WriteLn('never ', s);
end;

procedure Outer;
var q, k: LongInt;
begin
  q := 7;
  for k := 1 to 50 do q := q + k;
  try
    Through;
  except
    on E: Exception do WriteLn('O q=', q);
  end;
end;

var g: LongInt;
begin
  Widths;
  AllOps;
  SelfAndConst;
  Checked;
  InTry;
  g := 5; ByRef(g, 100); WriteLn('B g=', g);
  Params(7, 3);
  Ptrs;
  RaisesThrough;
  Outer;
end.
