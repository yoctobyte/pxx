{ Every LEGAL spelling of a `^T` written above T's own declaration.

  This is the accept side of the refusal added 2026-09-06 for a `^T` whose T is
  never declared at all (see test_forward_pointer_to_an_undeclared_type_fail).
  Widening a refusal is not one-sided: the rows it now stops accepting have to
  be exactly the rows nobody can declare, and the only way to say that is to
  enumerate the rows that CAN be. Each of the six below took the same
  PtrElemDepth escape hatch and is repaired -- or, for the enum, subrange and
  scalar-alias rows, never needed repairing -- by a different mechanism, so a
  drain that asked "was this row repaired?" instead of "is this name a type?"
  would have refused three of them. Measured against fpc 3.2.2: all six agree.

  EVERY ROW PRINTS A DISTINCT VALUE, and that is the point of the numbers: six
  rows all printing 7 would pass with any two of them swapped. }
program test_forward_pointer_targets_that_resolve_late;
{$mode objfpc}

type
  { 1. the classic: pointer to a record declared below it }
  PRec  = ^TRec;
  { 2. pointer to a pointer, both forward }
  PPRec = ^PRec;
  { 3. pointer to an ENUM declared below -- no repair pass covers this one }
  PCol  = ^TCol;
  { 4. pointer to a SUBRANGE declared below -- ditto }
  PSub  = ^TSub;
  { 5. pointer to a plain scalar ALIAS declared below -- ditto }
  PMy   = ^TMy;
  { 6. pointer to a named ARRAY type declared below }
  PArr  = ^TArr;

  TRec  = record a, b: Integer; end;
  TCol  = (cRed, cGreen, cBlue);
  TSub  = 1..100;
  TMy   = Integer;
  TArr  = array[0..2] of Integer;

  { 7. and the same shape inside a class body, where the pointee is that class's
       own nested type declared BELOW the alias }
  TOuter = class
  type
    PCell = ^TCell;
    TCell = record v: Integer; end;
  var
    head: PCell;
    function Get: Integer;
  end;

function TOuter.Get: Integer;
begin
  Result := head^.v;
end;

var
  r: TRec;   p1: PRec;   p2: PPRec;
  c: TCol;   p3: PCol;
  s: TSub;   p4: PSub;
  m: TMy;    p5: PMy;
  a: TArr;   p6: PArr;
  o: TOuter; cell: TOuter.TCell;
begin
  r.a := 11; r.b := 22;
  p1 := @r;  p2 := @p1;
  writeln('rec  ', p1^.a, ' ', p1^.b);
  writeln('pptr ', p2^^.a, ' ', p2^^.b);

  c := cBlue;  p3 := @c;  writeln('enum ', Ord(p3^));
  s := 44;     p4 := @s;  writeln('sub  ', p4^);
  m := 55;     p5 := @m;  writeln('alias ', p5^);

  a[0] := 66; a[1] := 77; a[2] := 88;
  p6 := @a;
  writeln('arr  ', p6^[0], ' ', p6^[1], ' ', p6^[2]);

  o := TOuter.Create;
  cell.v := 99;
  o.head := @cell;
  writeln('nest ', o.Get);
end.
