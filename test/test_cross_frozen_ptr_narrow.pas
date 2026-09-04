program test_cross_frozen_ptr_narrow;

{ A NARROW frozen string (`string[N]`, N <= 255 -- tyShortString, ONE length
  byte) reached through a POINTER, on all seven targets.

  The sibling file test_cross_frozen_ptr_in_field.pas uses cap 256 on purpose,
  which is tyString and an EIGHT-byte prefix. This one is the other layout, and
  it was wrong on EVERY target -- not just wasm32 -- because a deref lost the
  shortstring kind: StrValTk flattens tyShortString to tyString for every value
  node, IRFrozenKindOfAddr recovers the width from the SYMBOL, and a pointer
  that came out of a record FIELD has no symbol to recover it from. Measured
  against FPC before the fix, for `NamePtr: ^string[16]` holding 'AB':

    pxx  cmp FALSE  assign [16 blanks]  len 4342018  print [garbage]  idx [ ]
    fpc  cmp TRUE   assign [AB]         len 2        print [AB]       idx [A]

  and the whole program below SEGFAULTS on the pre-fix compiler, because the
  concat row reads a 1-byte prefix as an 8-byte length.

  IT PRINTS VALUES, NOT VERDICTS. `len` and the indexed character are the two
  quantities the wrong prefix width actually moves; a row that asserted only
  `= 'AB'` passes on a compare that reads both sides at the same wrong width,
  which is exactly how the ordering half of this defect class hid for a day.

  THE ROWS THAT ALREADY WORKED ARE HALF THE TEST. `q^` through a plain pointer
  VARIABLE was correct before the fix (its symbol carries PtrElemTk), and so
  were a plain `string[N]` FIELD and a plain ARRAY ELEMENT. They are asserted
  beside the broken ones so the file fails in both directions: a fix that
  reaches the pointee by always taking the address breaks the first, and one
  that always loads breaks the other two.

  Cap 16 and cap 255 are both present because 255 is the boundary of the narrow
  layout and a width table that is off by one at the top would pass at 16.
  bug-a-a-pointer-deref-loses-the-shortstring-kind-on-every-target }

type
  T16  = string[16];  P16  = ^T16;
  T255 = string[255]; P255 = ^T255;
  TRec16  = record NamePtr: P16;  F: T16;  end;
  TRec255 = record NamePtr: P255; F: T255; end;

var
  s16: T16;   s255: T255;
  r16: TRec16; r255: TRec255;
  q16: P16;   q255: P255;
  pr16: ^TRec16;
  ents: array[0..1] of TRec16;
  arr: array[0..2] of T16;
  cat: string;
  ok: Boolean;

procedure Row(const tag: string; cmp: Boolean; const asg: string;
              ln: LongInt; const pr, ct: string; ix: Char);
begin
  Write(tag, ' ');
  if cmp then Write('T') else Write('F');
  WriteLn(' [', asg, '] ', ln, ' [', pr, '] [', ct, '] ', ix);
  if not (cmp and (asg = 'AB') and (ln = 2) and (pr = 'AB')
          and (ct = 'xAB') and (ix = 'A')) then ok := False;
end;

begin
  ok := True;
  s16 := 'AB';  r16.NamePtr := @s16;   q16 := @s16;   r16.F := 'AB';
  s255 := 'AB'; r255.NamePtr := @s255; q255 := @s255; r255.F := 'AB';
  pr16 := @r16;
  ents[1].NamePtr := @s16;
  arr[1] := 'AB';

  { the four shapes whose pointer comes out of a FIELD -- all six columns of
    each were wrong before the fix }
  cat := 'x' + r16.NamePtr^;
  Row('fld16 ', r16.NamePtr^ = 'AB', r16.NamePtr^, Length(r16.NamePtr^),
      r16.NamePtr^, cat, r16.NamePtr^[1]);
  cat := 'x' + r255.NamePtr^;
  Row('fld255', r255.NamePtr^ = 'AB', r255.NamePtr^, Length(r255.NamePtr^),
      r255.NamePtr^, cat, r255.NamePtr^[1]);
  cat := 'x' + pr16^.NamePtr^;
  Row('prec16', pr16^.NamePtr^ = 'AB', pr16^.NamePtr^, Length(pr16^.NamePtr^),
      pr16^.NamePtr^, cat, pr16^.NamePtr^[1]);
  cat := 'x' + ents[1].NamePtr^;
  Row('elem16', ents[1].NamePtr^ = 'AB', ents[1].NamePtr^,
      Length(ents[1].NamePtr^), ents[1].NamePtr^, cat, ents[1].NamePtr^[1]);

  { the control rows -- correct before the fix and required to stay correct }
  cat := 'x' + q16^;
  Row('ptr16 ', q16^ = 'AB', q16^, Length(q16^), q16^, cat, q16^[1]);
  cat := 'x' + q255^;
  Row('ptr255', q255^ = 'AB', q255^, Length(q255^), q255^, cat, q255^[1]);
  cat := 'x' + r16.F;
  Row('pfld16', r16.F = 'AB', r16.F, Length(r16.F), r16.F, cat, r16.F[1]);
  cat := 'x' + arr[1];
  Row('arr16 ', arr[1] = 'AB', arr[1], Length(arr[1]), arr[1], cat, arr[1][1]);

  if ok then WriteLn('FROZENPTRNARROW OK') else WriteLn('FROZENPTRNARROW FAIL');
end.
