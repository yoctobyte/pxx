program test_mgmt_operators_copy_beside_a_managed_field;
{ A record mixing AnsiString fields with Copy-operator fields: the operators
  must run (they were skipped; the fused ARC copy moved their bytes) and the
  strings must still be retained. The output is fpc 3.2.2's.
  bug-a-a-record-mixing-an-arc-field-with-a-copy-operator-field-skips-the-operator }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
uses sysutils;
type
  TA = record
    id: Integer;
    class operator Copy(constref src: TA; var dst: TA);
  end;
  TMixed = record
    s: AnsiString;
    a: TA;
    k: Integer;
    t: AnsiString;
    b: TA;
  end;
var calls: Integer = 0;
class operator TA.Copy(constref src: TA; var dst: TA);
begin
  Inc(calls);
  if calls <= 2 then WriteLn('A.Copy src=', src.id, ' dst-on-entry=', dst.id);
  dst.id := dst.id + 1000;
end;
function Make(const x: AnsiString): TMixed;
begin
  Result.s := x + '!'; Result.t := 'tail-' + x; Result.a.id := 1; Result.b.id := 2; Result.k := 3;
end;
var m1, m2: TMixed; i: Integer; acc: AnsiString;
begin
  m1.s := 'from-' + 'one'; m1.a.id := 42; m1.k := 7; m1.t := 'x' + 'y'; m1.b.id := 43;
  m2.a.id := 99; m2.b.id := 98;
  m2 := m1;
  WriteLn('m2.s=', m2.s, ' m2.a.id=', m2.a.id, ' m2.k=', m2.k, ' m2.t=', m2.t, ' m2.b.id=', m2.b.id);
  m1.s := 'changed'; WriteLn('m2.s still ', m2.s);
  acc := '';
  for i := 1 to 2000 do
  begin
    m2 := m1;
    m1.s := 'n' + IntToStr(i mod 7);
  end;
  WriteLn(m2.s, ' ', m1.s, ' calls=', calls);
  m2 := Make('q');
  WriteLn(m2.s, ' ', m2.t, ' ', m2.a.id, ' ', m2.b.id);
end.
