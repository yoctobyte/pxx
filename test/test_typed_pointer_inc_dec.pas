{ `Inc(p)` on a TYPED pointer stepped ONE BYTE instead of SizeOf(element), and
  `Dec(p)` stepped one byte backwards -- silently, so a pointer walk just read
  from the wrong offset:

    p := @ar[0];  Inc(p);  writeln(p^);   { was 50331648, FPC: 3 }

  Every other spelling of the same step was correct: `Inc(p, 1)`, `Inc(p, 2)`,
  `p + 1`, `p[k]`, `(p + k)^`. Inc/Dec lower to `p := p +/- step`, and the
  step node for the IMPLICIT 1 was allocated without a type tag, so it read as
  tyUnknown and pointer arithmetic declined to scale it. One line, one concept,
  two paths -- see devdocs/dev/normalise-dont-special-case.md.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-inc-of-a-typed-pointer-steps-one-byte }
program test_typed_pointer_inc_dec;
{$mode objfpc}{$H+}
uses sysutils;

type
  PInt  = ^Integer;
  PI64  = ^Int64;
  PSm   = ^SmallInt;
  PByt  = ^Byte;
  PDbl  = ^Double;
  TR    = record a, b: Int64; end;
  PR    = ^TR;

var
  ok, total: Integer;
  ar: array[0..7] of Integer;
  a64: array[0..3] of Int64;
  sm: array[0..7] of SmallInt;
  by: array[0..7] of Byte;
  db: array[0..3] of Double;
  rs: array[0..3] of TR;
  p: PInt; q: PI64; r: PSm; pb: PByt; pd: PDbl; prc: PR;
  i: Integer; base: PtrUInt;

procedure Chk(const what: string; got, want: Int64);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;
  for i := 0 to 7 do ar[i] := i * 3;
  for i := 0 to 3 do a64[i] := i * 100;
  for i := 0 to 7 do sm[i] := i * 5;
  for i := 0 to 7 do by[i] := i * 2;
  for i := 0 to 3 do db[i] := i;
  for i := 0 to 3 do begin rs[i].a := i; rs[i].b := i * 10; end;

  { ---- the byte STEP itself, per element size ---- }
  p := @ar[0]; base := PtrUInt(p);
  Inc(p);   Chk('Inc(PInt) step', PtrUInt(p) - base, 4);
  Chk('Inc(PInt) value', p^, 3);
  Inc(p);   Chk('Inc(PInt) twice step', PtrUInt(p) - base, 8);
  Chk('Inc(PInt) twice value', p^, 6);
  Dec(p);   Chk('Dec(PInt) step', PtrUInt(p) - base, 4);
  Chk('Dec(PInt) value', p^, 3);
  Dec(p);   Chk('Dec(PInt) back to base', PtrUInt(p) - base, 0);
  Chk('Dec(PInt) base value', p^, 0);

  q := @a64[0]; base := PtrUInt(q);
  Inc(q);   Chk('Inc(PInt64) step', PtrUInt(q) - base, 8);
  Chk('Inc(PInt64) value', q^, 100);
  Dec(q);   Chk('Dec(PInt64) step', PtrUInt(q) - base, 0);

  r := @sm[0]; base := PtrUInt(r);
  Inc(r);   Chk('Inc(PSmallInt) step', PtrUInt(r) - base, 2);
  Chk('Inc(PSmallInt) value', r^, 5);

  pb := @by[0]; base := PtrUInt(pb);
  Inc(pb);  Chk('Inc(PByte) step', PtrUInt(pb) - base, 1);
  Chk('Inc(PByte) value', pb^, 2);

  pd := @db[0]; base := PtrUInt(pd);
  Inc(pd);  Chk('Inc(PDouble) step', PtrUInt(pd) - base, 8);
  Chk('Inc(PDouble) value', Trunc(pd^), 1);

  prc := @rs[0]; base := PtrUInt(prc);
  Inc(prc);  Chk('Inc(PRec) step', PtrUInt(prc) - base, 16);
  Chk('Inc(PRec) value', prc^.a, 1);
  Chk('Inc(PRec) second field', prc^.b, 10);

  { ---- the spellings that were already right, so the fix did not move them ---- }
  p := @ar[0]; base := PtrUInt(p);
  Inc(p, 1); Chk('Inc(p,1) step', PtrUInt(p) - base, 4);
  Inc(p, 2); Chk('Inc(p,2) step', PtrUInt(p) - base, 12);
  Chk('Inc(p,2) value', p^, 9);
  Dec(p, 3); Chk('Dec(p,3) step', PtrUInt(p) - base, 0);
  p := @ar[0]; p := p + 1;
  Chk('p + 1 step', PtrUInt(p) - base, 4);
  Chk('p + 1 value', p^, 3);
  p := @ar[0];
  Chk('p[2]', p[2], 6);
  Chk('(p+3)^', (p + 3)^, 9);
  Inc(p, 0); Chk('Inc(p,0) is a no-op', PtrUInt(p) - base, 0);

  { ---- an ordinary integer Inc/Dec must be unchanged ---- }
  i := 5; Inc(i);      Chk('Inc(Integer)', i, 6);
  Inc(i, 4);           Chk('Inc(Integer,4)', i, 10);
  Dec(i);              Chk('Dec(Integer)', i, 9);
  Dec(i, 3);           Chk('Dec(Integer,3)', i, 6);

  { ---- and a walk of the kind real code writes ---- }
  p := @ar[0];
  base := 0;
  for i := 0 to 7 do begin base := base + PtrUInt(p^); Inc(p); end;
  Chk('walked sum', base, 84);

  writeln('total ok ', ok, ' / ', total);
end.
