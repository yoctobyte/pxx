program test_open_array_of_a_named_dynamic_array;
{ An open-array parameter whose ELEMENT is a named DYNAMIC array
  (`const m: array of TRow`, `TRow = array of Integer`): each element is a
  pointer-sized dyn-array HANDLE, not a base scalar. The parameter used to be
  typed as `array of <element base type>`, so the callee indexed it with the
  base stride and read garbage — 124906597515344 where FPC printed 3 — and a
  slightly larger shape segfaulted. Every row below is checked against
  `fpc -Mobjfpc`. }

type
  TRow  = array of Integer;
  TStrs = array of string;
  TRec  = record a, b: Integer; end;
  TFix  = array[0..1] of Integer;

var
  fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got = want then Writeln(what, ' ok')
  else begin Writeln(what, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got = want then Writeln(what, ' ok')
  else begin Writeln(what, ' FAIL got=[', got, '] want=[', want, ']'); Inc(fails); end;
end;

{ --- the broken shape, in every parameter mode --- }

procedure ByConst(const m: array of TRow);
begin
  Chk('const.len',   Length(m),    3);
  Chk('const.row0',  Length(m[0]), 2);
  Chk('const.e01',   m[0][1],      2);
  Chk('const.e10',   m[1][0],      3);
  Chk('const.row2',  Length(m[2]), 0);
  Chk('const.high',  High(m),      2);
end;

procedure ByConst2(const m: array of TRow);
begin
  Chk('ctor.len',  Length(m),    2);
  Chk('ctor.row0', Length(m[0]), 2);
  Chk('ctor.e01',  m[0][1],      6);
  Chk('ctor.e10',  m[1][0],      7);
end;

procedure ByValue(m: array of TRow);
begin
  Chk('value.len',   Length(m),    3);
  Chk('value.e01',   m[0][1],      2);
end;

procedure ByVar(var m: array of TRow);
begin
  m[0][0] := 99;
  SetLength(m[1], 4);
  m[1][3] := 77;
  Chk('var.write',   m[0][0],      99);
  Chk('var.setlen',  Length(m[1]), 4);
  Chk('var.deep',    m[1][3],      77);
end;

{ --- element base types that were already right, kept as the control row --- }

procedure ElemStr(const m: array of TStrs);
begin
  Chk ('str.len',  Length(m[0]), 2);
  ChkS('str.e01',  m[0][1],      'y');
  ChkS('str.e10',  m[1][0],      'z');
end;

procedure ElemRec(const m: array of TRec);
begin
  Chk('rec.a', m[0].a, 1);
  Chk('rec.b', m[1].b, 2);
end;

procedure ElemFix(const m: array of TFix);
begin
  Chk('fix.a', m[0][1], 5);
  Chk('fix.b', m[1][0], 6);
end;

procedure ElemPtr(const m: array of Pointer);
begin
  Chk('ptr.a', Ord(m[0] = nil), 1);
  Chk('ptr.b', Ord(m[1] = nil), 0);
end;

var
  r: array of TRow;
  q: array of TStrs;
  c: array of TRec;
  f: array of TFix;
  p: array of Pointer;
  a, b: TRow;
  i: Integer;

begin
  fails := 0;

  SetLength(r, 3);
  SetLength(r[0], 2); r[0][0] := 1; r[0][1] := 2;
  SetLength(r[1], 1); r[1][0] := 3;
  SetLength(r[2], 0);
  ByConst(r);
  ByValue(r);
  ByVar(r);
  { the var param wrote through to the caller's rows }
  Chk('caller.write',  r[0][0],      99);
  Chk('caller.setlen', Length(r[1]), 4);
  Chk('caller.deep',   r[1][3],      77);

  { an array CONSTRUCTOR in the same position: the temp must be a dyn array OF
    dyn handles, not of the element base type (it stored a handle into a 4-byte
    Integer slot and segfaulted). }
  SetLength(a, 2); a[0] := 5; a[1] := 6;
  SetLength(b, 1); b[0] := 7;
  ByConst2([a, b]);

  SetLength(q, 2);
  SetLength(q[0], 2); q[0][0] := 'x'; q[0][1] := 'y';
  SetLength(q[1], 1); q[1][0] := 'z';
  ElemStr(q);

  SetLength(c, 2); c[0].a := 1; c[1].b := 2; ElemRec(c);
  SetLength(f, 2); f[0][1] := 5; f[1][0] := 6; ElemFix(f);
  SetLength(p, 2); p[0] := nil;  p[1] := @r;  ElemPtr(p);

  { iterating the parameter, the shape the original finding crashed on }
  i := 0;
  for i := 0 to High(r) do
    if Length(r[i]) > 4 then Inc(fails);

  if fails = 0 then Writeln('ALL OK') else Writeln('FAILURES: ', fails);
end.
