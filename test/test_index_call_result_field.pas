{ Indexing a function CALL RESULT, then selecting a field on the element.

  `ResolveNodeRec`'s AN_INDEX arm had a case for every base kind — an ident, a
  field, a nested index, an address-of, a pointer cast — except a CALL. So
  `MkR[i]` resolved to REC_NONE, the field lookup found nothing, and the
  `.field` was applied at OFFSET 0: every field of the element answered the
  FIRST field, silently and with no diagnostic.

  It could not be reached before the Result slot itself was allocated as an
  array (bug-a-nd-array-function-result-indexes-the-wrong-slot), which is why
  a shape FPC has always accepted was never observed to be wrong.

  Both rows diffed against FPC.
  bug-a-indexing-a-function-call-result-drops-the-field-selector }
program test_index_call_result_field;
type
  TRec  = record a, b, c: Integer; end;
  TArrR = array[0..1] of TRec;
  TArr2R = array[0..1, 0..1] of TRec;

function MkR: TArrR;
begin
  MkR[0].a := 1; MkR[0].b := 2; MkR[0].c := 3;
  MkR[1].a := 4; MkR[1].b := 5; MkR[1].c := 6;
end;

function MkR2: TArr2R;
begin
  MkR2[0,0].a := 1; MkR2[0,0].b := 2; MkR2[0,0].c := 3;
  MkR2[1,1].a := 7; MkR2[1,1].b := 8; MkR2[1,1].c := 9;
end;

var v: TArrR; w: TArr2R;
begin
  { the control: the same access through a variable was always right }
  v := MkR;
  WriteLn('via var   ', v[0].a, ' ', v[0].b, ' ', v[0].c, ' ',
                        v[1].a, ' ', v[1].b, ' ', v[1].c);
  { the bug: 1 1 1 4 4 4 — the subscript applied, the selector dropped }
  WriteLn('on call   ', MkR[0].a, ' ', MkR[0].b, ' ', MkR[0].c, ' ',
                        MkR[1].a, ' ', MkR[1].b, ' ', MkR[1].c);

  w := MkR2;
  WriteLn('nd var    ', w[0,0].a, ' ', w[0,0].b, ' ', w[0,0].c, ' ',
                        w[1,1].a, ' ', w[1,1].b, ' ', w[1,1].c);
  { `MkR2[0,0].a` — the N-D subscript directly on the call — does NOT parse
    yet: the selector walker's bracket arm reads ONE expression, and flattening
    a multi-index needs the dim spans, which the call node does not carry.
    Still open on the ticket; not asserted here so nothing blesses either
    answer. }
  WriteLn('INDEX CALL RESULT FIELD OK');
end.
