program test_byvalue_record_managed_copy;
{$mode objfpc}{$H+}

{ bug-byvalue-record-managed-field-aliases-caller: a record passed by plain
  value (no var/const) must be an independent copy -- writes inside the
  callee must not leak back to the caller. This held for small/plain
  records, but a record over 8 bytes is passed via a hidden by-ref ABI slot
  for efficiency, and that ABI promotion was leaking straight through to the
  caller's own storage for ANY plain record over 8 bytes (managed-field or
  not) since only a genuine var/out/const param is supposed to alias. }

type
  TPlain = record a, b: integer; end;              { 8 bytes: value-ABI path }
  TBig   = record a, b, c: integer; end;            { 12 bytes: by-ref-for-ABI path, no managed field }
  TMan   = record a: integer; s: string; end;       { 16 bytes: by-ref-for-ABI path, managed field }

procedure modPlain(r: TPlain); begin r.a := 999; r.b := 888; end;
procedure modBig(r: TBig); begin r.a := 999; r.b := 888; r.c := 777; end;
procedure modMan(r: TMan); begin r.a := 999; r.s := 'changed'; end;
procedure modManConst(const r: TMan); begin writeln(r.a, ',', r.s); end;
procedure modManVar(var r: TMan); begin r.a := 111; r.s := 'viavar'; end;

function makeMan(v: integer): TMan;
begin
  makeMan.a := v;
  makeMan.s := 'made';
end;
procedure modManVal(r: TMan); begin r.a := 555; r.s := 'byval'; end;

var
  p: TPlain;
  b: TBig;
  m: TMan;
  s1: string;
begin
  p.a := 1; p.b := 2;
  modPlain(p);
  writeln(p.a, ',', p.b);

  b.a := 1; b.b := 2; b.c := 3;
  modBig(b);
  writeln(b.a, ',', b.b, ',', b.c);

  m.a := 1; m.s := 'orig'; modMan(m);
  writeln(m.a, ',', m.s);

  m.a := 5; m.s := 'view';
  modManConst(m);
  writeln(m.a, ',', m.s);

  m.a := 5; m.s := 'before';
  modManVar(m);
  writeln(m.a, ',', m.s);

  m.a := 2; m.s := 'orig2';
  modManVal(makeMan(42));
  writeln(m.a, ',', m.s);

  { independent-copy check: a fresh managed string in the copy must not be
    aliased to the original (ARC'd correctly, not a shallow/shared handle) }
  m.a := 9; m.s := 'shared?';
  s1 := m.s;
  modMan(m);
  writeln(s1);
end.
