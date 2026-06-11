program test_cross_record;
{ Managed records (records with AnsiString fields) on cross targets, compiled
  with -dPXX_MANAGED_STRING. Exercises the Tier B layout-RTTI helpers:
  ARC-correct whole-record copy (PXXRecordRetain/Release) with field
  independence, plus plain (unmanaged) record copy > 8 bytes. Output is
  identical on every target (oracle pattern). }

type
  TPerson = record name: AnsiString; age: Integer; end;
  TBig = record a, b, c, d: Integer; end;   { > 8 bytes, no managed fields }

var p, q: TPerson; x, y: TBig;
begin
  { managed record copy: q gets its own retained copy of p.name }
  p.name := 'Alice'; p.age := 30;
  q := p;
  p.name := 'Bob';                  { mutating p must not touch q }
  writeln(q.name, ' ', q.age);      { Alice 30 }
  writeln(p.name, ' ', p.age);      { Bob 30 }

  { reassignment releases q's old field and retains the new }
  q := p;
  writeln(q.name);                  { Bob }

  { plain record copy (rep movsb of the full struct) }
  x.a := 1; x.b := 2; x.c := 3; x.d := 4;
  y := x;
  x.a := 99;
  writeln(y.a + y.b + y.c + y.d);   { 10 }
end.
