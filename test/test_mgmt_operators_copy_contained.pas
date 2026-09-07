program test_mgmt_operators_copy_contained;
{ `class operator Copy` on a field of the record being assigned. The record
  itself declares NO operator; a whole-record assignment must still run the
  CONTAINED one, once per contained field, and copy everything else as bytes.

  WHY THE OPERATOR PRINTS AND NOTHING COMPARES THE COPIED VALUE. An operator
  that dutifully copies its fields is indistinguishable from no operator at all:
  both leave the destination holding the source's values, because the bulk copy
  would have moved the same bytes. So TA.Copy assigns `id` and DELIBERATELY
  leaves `pad` alone, and the rows print `pad` — with the operator running,
  `pad` keeps the DESTINATION's value; without it, the bytes arrive.

  DST-ON-ENTRY IS PRINTED because the destination is not bulk-copied first.
  Measured against fpc 3.2.2: a contained Copy field is DELEGATED ENTIRELY, so
  the operator sees dst's OLD value. A lowering that copied the whole record and
  then called the operator prints the SOURCE's number here and is wrong for any
  operator that reads dst.

  THE GAPS ARE PART OF THE CLAIM. THolder puts a plain field BEFORE the operator
  field and another AFTER it, so a lowering that punched the hole but forgot a
  gap loses `lead` or `k`. TMulti has a gap BETWEEN two holes.

  DECLARATION ORDER, and ASCENDING for an array field: both measured under fpc,
  both pinned below (A before B; arr[0] before arr[1]).

  ABSENT ON PURPOSE, and each is a named residual on
  bug-a-a-whole-record-assignment-does-not-run-a-contained-fields-copy-operator:
  - a whole-STATIC-ARRAY assignment (`d := s` for `array[0..1] of THolder`) is a
    different lowering site and does not fire yet;
  - a record mixing an ARC field (AnsiString, dynamic array) with an operator
    field is REFUSED: IR_COPY_REC_MANAGED is a fused retain-release-copy that
    cannot be handed a byte range, so that shape keeps today's answer.
  Adding either row here would make this fixture red rather than make the
  compiler right, and the ticket is where the measurement lives. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TA = record
    id: Integer;
    pad: Integer;
    class operator Copy(constref src: TA; var dst: TA);
  end;
  TB = record
    id: Integer;
    pad: Integer;
    class operator Copy(constref src: TB; var dst: TB);
  end;
  { lead .. f .. k — a gap on BOTH sides of the hole }
  THolder = record
    lead: Integer;
    f: TA;
    k: Integer;
  end;
  { two holes with a gap between them }
  TMulti = record
    a: TA;
    k: Integer;
    b: TB;
  end;
  TOuter = record
    m: TMulti;
    z: Integer;
  end;
  TArrF = record
    arr: array[0..1] of TA;
    k: Integer;
  end;
  { the outer operator REPLACES the whole copy — the contained one must not
    also fire }
  TShadow = record
    f: TA;
    k: Integer;
    class operator Copy(constref src: TShadow; var dst: TShadow);
  end;
  { no operator anywhere: the control that must stay a plain bulk copy }
  TPlain = record
    x: Integer;
    y: Integer;
  end;
  TPlainHolder = record
    p: TPlain;
    k: Integer;
  end;

class operator TA.Copy(constref src: TA; var dst: TA);
begin
  writeln('  A.Copy src.id=', src.id, ' dst.id-on-entry=', dst.id);
  dst.id := src.id;
end;

class operator TB.Copy(constref src: TB; var dst: TB);
begin
  writeln('  B.Copy src.id=', src.id, ' dst.id-on-entry=', dst.id);
  dst.id := src.id;
end;

class operator TShadow.Copy(constref src: TShadow; var dst: TShadow);
begin
  writeln('  Shadow.Copy src.k=', src.k, ' dst.k-on-entry=', dst.k);
end;

procedure PlainHole;
var h1, h2: THolder;
begin
  h1.lead := 11; h1.f.id := 1; h1.f.pad := 111; h1.k := 22;
  h2.lead := 55; h2.f.id := 9; h2.f.pad := 999; h2.k := 66;
  writeln('-- holder: h2 := h1');
  h2 := h1;
  writeln('   lead=', h2.lead, ' f.id=', h2.f.id, ' f.pad=', h2.f.pad, ' k=', h2.k);
end;

procedure TwoHoles;
var m1, m2: TMulti;
begin
  m1.a.id := 1; m1.a.pad := 111; m1.k := 2; m1.b.id := 3; m1.b.pad := 333;
  m2.a.id := 7; m2.a.pad := 777; m2.k := 8; m2.b.id := 9; m2.b.pad := 999;
  writeln('-- multi: m2 := m1');
  m2 := m1;
  writeln('   a.id=', m2.a.id, ' a.pad=', m2.a.pad, ' k=', m2.k,
          ' b.id=', m2.b.id, ' b.pad=', m2.b.pad);
end;

procedure Nested;
var o1, o2: TOuter;
begin
  o1.m.a.id := 10; o1.m.a.pad := 110; o1.m.k := 20;
  o1.m.b.id := 30; o1.m.b.pad := 130; o1.z := 40;
  o2.m.a.id := 70; o2.m.a.pad := 170; o2.m.k := 80;
  o2.m.b.id := 90; o2.m.b.pad := 190; o2.z := 99;
  writeln('-- nested: o2 := o1');
  o2 := o1;
  writeln('   a.id=', o2.m.a.id, ' a.pad=', o2.m.a.pad, ' k=', o2.m.k,
          ' b.id=', o2.m.b.id, ' b.pad=', o2.m.b.pad, ' z=', o2.z);
end;

procedure ArrayField;
var f1, f2: TArrF;
begin
  f1.arr[0].id := 100; f1.arr[0].pad := 1100;
  f1.arr[1].id := 200; f1.arr[1].pad := 1200;
  f1.k := 300;
  f2.arr[0].id := 700; f2.arr[0].pad := 1700;
  f2.arr[1].id := 800; f2.arr[1].pad := 1800;
  f2.k := 900;
  writeln('-- array field: f2 := f1');
  f2 := f1;
  writeln('   [0].id=', f2.arr[0].id, ' [0].pad=', f2.arr[0].pad,
          ' [1].id=', f2.arr[1].id, ' [1].pad=', f2.arr[1].pad, ' k=', f2.k);
end;

procedure OuterShadowsInner;
var s1, s2: TShadow;
begin
  s1.f.id := 1; s1.f.pad := 111; s1.k := 2;
  s2.f.id := 7; s2.f.pad := 777; s2.k := 8;
  writeln('-- shadow: s2 := s1');
  s2 := s1;
  writeln('   f.id=', s2.f.id, ' f.pad=', s2.f.pad, ' k=', s2.k);
end;

procedure NoOperatorAnywhere;
var p1, p2: TPlainHolder;
begin
  p1.p.x := 1; p1.p.y := 2; p1.k := 3;
  p2.p.x := 7; p2.p.y := 8; p2.k := 9;
  writeln('-- control: p2 := p1 (no operator anywhere)');
  p2 := p1;
  writeln('   x=', p2.p.x, ' y=', p2.p.y, ' k=', p2.k);
end;

begin
  PlainHole;
  TwoHoles;
  Nested;
  ArrayField;
  OuterShadowsInner;
  NoOperatorAnywhere;
  writeln('done');
end.
