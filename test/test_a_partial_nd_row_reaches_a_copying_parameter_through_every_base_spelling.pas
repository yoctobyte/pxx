program test_a_partial_nd_row_reaches_a_copying_parameter_through_every_base_spelling;
{ refactor-p-nodearrndinfo-yields-spans-but-not-the-element

  NodeArrNDInfo resolves an array reference through FOUR arms -- a plain
  identifier, a record field, and the two halves of a deref (the pointer
  SYMBOL, and the pointee's ArrType row) -- and published the dimension spans
  and nothing else. So every caller that needed to know what an ELEMENT IS
  re-opened the spelling question one line after the function had answered it,
  with its own AN_IDENT / AN_FIELD / AN_DEREF switch. Track C's CNodeArrayShape
  was literally that: a wrapper whose whole body was the second switch, run
  again. THREE SHIPPED C BUGS WERE ALL A MISSING FIELD HALF OF THAT SECOND
  SWITCH -- a struct field's partial index using the outer row stride, a
  multi-dim array field decaying with the element stride, and sizeof of a
  partial index answering the element rather than the row.

  The element is published beside the spans now, filled in whichever arm
  matched, and NDRowSourceInfo's copy of the switch is deleted. This file is
  the regression guard on that deletion: it drives a partial N-D row into a
  COPYING parameter through every base spelling, which is the path
  NDRowSourceInfo exists to serve.

  WHAT THE ABLATION SHOWED, AND IT IS NOT ALL GOOD NEWS. Setting the field
  arm's NDInfoElemTk to tyUnknown and rebuilding breaks row 3 -- so that column
  is genuinely guarded here. Setting the field arm's NDInfoElemRec to REC_NONE
  and rebuilding changes NOTHING on any row, including the record-element ones.
  So THIS FILE DOES NOT COVER NDInfoElemRec, and saying it did would be the
  guard-that-cannot-fail. Whether that is because the consumer does not need
  the record id on this path, or because something downstream compensates for
  a missing one, is not established here and is not this file's question --
  it is written down so the next reader does not infer coverage from the
  presence of record elements.

  Every row is byte-identical to fpc 3.2.2. }

type
  TPt = record
    x, y: LongInt;
  end;
  TG  = array[0..1, 0..2] of LongInt;
  PG  = ^TG;
  TGR = array[0..1, 0..2] of TPt;
  PGR = ^TGR;
  TR  = record m: TG; end;
  TRR = record m: TGR; end;

var
  fails: Integer;
  g: TG;   r: TR;   p: PG;
  gr: TGR; rr: TRR; pr: PGR;
  i, j: LongInt;

{ A COPYING parameter -- `const` over an open array is by-reference-with-a-copy
  in the modes this path serves, and it is the mode the row used to segfault
  in. The callee reports what it RECEIVED, so a row that arrived as a scalar
  load of its first element shows up as a length rather than as a crash. }
procedure TakeInts(const a: array of LongInt; const what: AnsiString;
                   w0, w1, w2: LongInt);
begin
  if Length(a) <> 3 then
  begin
    WriteLn('FAIL ', what, ': length ', Length(a), ' want 3');
    fails := fails + 1;
    Exit;
  end;
  if (a[0] <> w0) or (a[1] <> w1) or (a[2] <> w2) then
  begin
    WriteLn('FAIL ', what, ': got ', a[0], ' ', a[1], ' ', a[2],
            ' want ', w0, ' ', w1, ' ', w2);
    fails := fails + 1;
  end;
end;

{ ...and the same with a RECORD element, because the element's SIZE is what
  drives the stride and a record is the shape where getting it wrong is
  visible rather than merely wrong-by-luck. }
procedure TakePts(const a: array of TPt; const what: AnsiString;
                  w0x, w1x, w2x: LongInt);
begin
  if Length(a) <> 3 then
  begin
    WriteLn('FAIL ', what, ': length ', Length(a), ' want 3');
    fails := fails + 1;
    Exit;
  end;
  if (a[0].x <> w0x) or (a[1].x <> w1x) or (a[2].x <> w2x) then
  begin
    WriteLn('FAIL ', what, ': got ', a[0].x, ' ', a[1].x, ' ', a[2].x,
            ' want ', w0x, ' ', w1x, ' ', w2x);
    fails := fails + 1;
  end;
  if (a[0].y <> w0x + 100) or (a[2].y <> w2x + 100) then
  begin
    WriteLn('FAIL ', what, ': the second field did not ride along');
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  for i := 0 to 1 do
    for j := 0 to 2 do
    begin
      g[i, j] := i * 10 + j;
      gr[i, j].x := i * 10 + j;
      gr[i, j].y := 100 + i * 10 + j;
    end;
  r.m := g;   p := @g;
  rr.m := gr; pr := @gr;

  { 1, 2: the IDENT base, both rows, so a stride that answered the outer
    dimension would put row 1's values under row 2's name. }
  TakeInts(g[0], '1: ident base, row 0', 0, 1, 2);
  TakeInts(g[1], '2: ident base, row 1', 10, 11, 12);

  { 3: the FIELD base -- the half whose absence at each caller's own second
    switch was three shipped C bugs, and the one column this file's ablation
    actually guards. }
  TakeInts(r.m[1], '3: field base', 10, 11, 12);

  { 4: the DEREF base. NodeArrNDInfo's deref arm resolves through
    DerefPtrArraySym while the deleted switch asked DerefPtrArrayElem, which
    asks DerefPtrArraySymAny -- a WIDER question. This row is why that
    difference was measured rather than reasoned about. }
  TakeInts(p^[0], '4: deref base', 0, 1, 2);

  { 5..8: the same four spellings with a RECORD element. }
  TakePts(gr[0], '5: ident base, record element', 0, 1, 2);
  TakePts(gr[1], '6: ident base, record element, row 1', 10, 11, 12);
  TakePts(rr.m[1], '7: field base, record element', 10, 11, 12);
  TakePts(pr^[0], '8: deref base, record element', 0, 1, 2);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('NDROWBASES OK');
end.
