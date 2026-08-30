program test_pointer_to_array_indexing;
{ `p^[i]` where p points at a named FIXED array, across every element kind.

  Every row here compares the pointer spelling against the DIRECT one on the
  same array, because the defect this test exists for was not "p^[i] crashes":
  the `[` arm chain dispatched on the node's tk, and on a pointer-to-array
  deref that tk is the ARRAY's ELEMENT kind. So the symptom depended on which
  arm the element kind collided with -- a pointer element crashed, an
  AnsiString element crashed, a string[7] element printed EMPTY and exited 0,
  and writing to one was refused as "cannot assign ShortString to Char".
  Four faces, one wrong answer.

  Hence: EXIT CODES PROVE NOTHING HERE. Four of the broken rows returned 0.
  Compare values, and keep an element kind from each arm the chain has --
  managed string, frozen string, pointer, record, ordinal.

  THE FROZEN-STRING ROW IS NOT EXTRA COVERAGE (frankB, and this is stronger
  than the version of it I first wrote). The bug had a second silent arm hiding
  BEHIND the first: clearing the arm chain routed `string[7]` past the
  frozen-string arm and into `elemSize := LOCAL_STR_CAP + 8` -- 264 bytes of
  stride for a 15-byte slot -- still empty, still exit 0, and by then every
  crash was fixed. So a sweep that stops when the segfaults stop is not merely
  incomplete: it has guaranteed it cannot see what is left. This row is the only
  one that can.
  bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds }
type
  TR = record a, b: Integer; end;
  TAI = array[0..3] of Integer;       PAI = ^TAI;
  TAP = array[0..3] of PChar;         PAP = ^TAP;
  TAS = array[0..3] of string[7];     PAS = ^TAS;
  TAA = array[0..3] of AnsiString;    PAA = ^TAA;
  TAR = array[0..3] of TR;            PAR = ^TAR;
  TLO = array[1..4] of PChar;         PLoArr = ^TLO;
  TND = array[0..1, 0..2] of Integer; PND = ^TND;
  TDY = array of Integer;             PDY = ^TDY;
var
  ai: TAI; ap: TAP; as_: TAS; aa: TAA; ar: TAR; alo: TLO; nd: TND; dy: TDY;
  pi_: PAI; pp: PAP; ps: PAS; pa: PAA; pr: PAR; qlo: PLoArr; pn: PND; pd: PDY;
  i: Integer; s: string[7];
begin
  { READ: direct spelling, then the same element through the pointer }
  ai[1] := 42;    pi_ := @ai;  WriteLn('int   ', ai[1],   ' ', pi_^[1]);
  ap[1] := 'hi';  pp := @ap;   WriteLn('pchar ', ap[1],   ' ', pp^[1]);
  as_[1] := 'hi'; ps := @as_;  WriteLn('str7  ', as_[1],  ' ', ps^[1]);
  aa[1] := 'hi';  pa := @aa;   WriteLn('ansi  ', aa[1],   ' ', pa^[1]);
  ar[1].a := 7;   pr := @ar;   WriteLn('rec   ', ar[1].a, ' ', pr^[1].a);
  alo[2] := 'lo'; qlo := @alo; WriteLn('lo1   ', alo[2],  ' ', qlo^[2]);

  { WRITE through the pointer, read back directly }
  pi_^[2] := 9;   WriteLn('wint  ', ai[2]);
  ps^[2] := 'ok'; WriteLn('wstr  ', as_[2]);
  pa^[2] := 'ok'; WriteLn('wansi ', aa[2]);
  pp^[2] := 'ok'; WriteLn('wpchr ', ap[2]);
  pr^[2].b := 5;  WriteLn('wrec  ', ar[2].b);
  qlo^[3] := 'ok';WriteLn('wlo1  ', alo[3]);

  { the extent queries over the same deref -- one low bound of 0, one of 1 }
  WriteLn('len   ', Length(pi_^), ' ', High(pi_^), ' ', Low(pi_^), ' ', SizeOf(pi_^));
  WriteLn('len1  ', Length(qlo^), ' ', High(qlo^), ' ', Low(qlo^));

  { a MULTI-DIM pointee: its subscripts are flattened before the low bounds are
    applied, so it must not be normalised a second time }
  nd[1,2] := 8; pn := @nd;
  WriteLn('nd    ', nd[1,2], ' ', pn^[1,2], ' ', Length(pn^), ' ', SizeOf(pn^));

  { a DYNAMIC pointee is a different shape on a different slot -- unaffected }
  SetLength(dy, 4); dy[1] := 3; pd := @dy;
  WriteLn('dyn   ', dy[1], ' ', pd^[1], ' ', Length(pd^));

  { positions other than Write, which is the one that reads a type tag }
  i := pi_^[1] + 1; WriteLn('expr  ', i);
  s := ps^[1];      WriteLn('asgn  ', s);
  for i := 0 to 3 do ai[i] := i;
  WriteLn('loop  ', pi_^[3]);
end.
