program test_a_whole_array_destination_takes_every_shape_the_census_found;
{ bug-p-a-whole-array-assignment-destination-is-never-type-checked

  THE POSITIVE CONTROL FOR A NARROWING, AND IT IS DRAWN FROM THE POPULATION THE
  NARROWING WAS MEASURED OVER -- not invented. `sa := s`, a managed string
  assigned to a whole static array of AnsiString, compiled and SIGSEGV'd; the
  refusal that fixes it sits above the kind funnel in ir.inc and it would start
  rejecting programs the tree compiles today, so PXXDBG=a.wholearr counted them
  first: 2109 files under test/ and examples/, 1834 compiled to the end, 1445
  whole-array assignment destinations.

  EVERY ROW BELOW IS ONE OF THE RIGHT-HAND-SIDE NODE KINDS THAT CENSUS SAW.
  That is the point of the file. A control written from imagination tests the
  shapes its author thought of; this one tests the shapes that are actually out
  there, in the proportions they are out there, and the four families that the
  FIRST candidate rule would have refused are rows 6 through 9. That rule --
  "the right-hand side must be positively array-SHAPED", which is what the
  ticket prescribed -- refused 49 legal sites in twelve files and ZERO
  instances of the defect, because no reader in the tree can say "this
  expression's VALUE is an array" for a call result or a row. The rule that
  landed asks the opposite question and refuses only what it can positively
  type as a NON-array.

  Rows 6-9 are therefore not decoration. If any of them ever starts failing to
  compile, the refusal has been rephrased into the shape the census rejected.

  The refusal half lives in test_a_whole_array_destination_refuses_a_scalar.pas,
  which cannot live here because it must not compile. }

type
  TSA3   = array[0..2] of LongInt;
  TDyn   = array of LongInt;
  TRows  = array of TSA3;          { a dynamic array whose ELEMENT is a fixed row }
  TMaker = function: TSA3;
  TC     = class
             SA: TSA3;
             DA: TDyn;
           end;

var
  fails: Integer;

procedure Chk(const what: AnsiString; got, want: LongInt);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

function MakeSA: TSA3;
begin
  MakeSA[0] := 7; MakeSA[1] := 8; MakeSA[2] := 9;
end;

{ Row 4's shape: an OPEN-ARRAY PARAMETER assigned to a dynamic array. fpc
  REJECTS this and we accept it deliberately, so it must survive by name --
  and nothing in the rule may ask a length, because AllocParam stamps
  ArrLen := 1000 on every array parameter as the open-array placeholder. }
function OpenToDyn(const o: array of LongInt): LongInt;
var t: TDyn;
begin
  t := o;
  OpenToDyn := Length(t);
end;

var
  sa, sb: TSA3;
  fx: TSA3;
  d, e: TDyn;
  rows: TRows;
  row: TSA3;
  c: TC;
  mk: TMaker;
  i: Integer;

begin
  fails := 0;

  { 1: whole static array := whole static array, both plain identifiers. }
  sb[0] := 1; sb[1] := 2; sb[2] := 3;
  sa := sb;
  Chk('1 static := static', sa[1], 2);

  { 2: dyn := dyn. Named in the ticket as a shape that must survive. }
  SetLength(e, 3); e[0] := 4; e[1] := 5; e[2] := 6;
  d := e;
  Chk('2 dyn := dyn', d[2], 6);

  { 3: dyn := nil, and dyn := Default(TDyn). Both reach the assignment as an
    INTEGER LITERAL zero -- Default of a dynamic array is already lowered by
    the time the rule runs -- which is why no literal may be refused here. }
  d := nil;
  Chk('3a dyn := nil', Length(d), 0);
  d := e;
  d := Default(TDyn);
  Chk('3b dyn := Default(TDyn)', Length(d), 0);

  { 4: an OPEN-ARRAY PARAMETER assigned to a dynamic array -- fpc rejects it,
    we accept it on purpose. }
  Chk('4 open param := dyn', OpenToDyn(sb), 3);

  { 5: a FIXED-length array assigned to a DYNAMIC one, which the neighbouring
    guard one screen down in ir.inc turns into an element-by-element copy. It
    is here because that guard REWRITES the right-hand side, and this rule must
    run ABOVE it or it would measure its neighbour's fix. }
  fx[0] := 11; fx[1] := 12; fx[2] := 13;
  d := fx;
  Chk('5 dyn := fixed', d[0] + d[1] + d[2], 36);

  { ---- rows 6-9: the four families the FIRST candidate rule refused ---- }

  { 6: a CALL returning a static array (35 of the 49 false refusals). }
  sa := MakeSA;
  Chk('6 static := call result', sa[0] + sa[1] + sa[2], 24);

  { 7: an INDEX that yields a fixed ROW out of a dynamic array (6 of them).
    The row is a whole array and the index has not selected an element. }
  SetLength(rows, 2);
  rows[1][0] := 21; rows[1][1] := 22; rows[1][2] := 23;
  row := rows[1];
  Chk('7 static := a row of a dyn array', row[2], 23);

  { 8: Default(T) on an AGGREGATE, which arrives as its own node kind (3). }
  sa := Default(TSA3);
  Chk('8 static := Default(aggregate)', sa[0] + sa[1] + sa[2], 0);

  { 9: an INDIRECT call through a procedural value (3 of them, with the
    interface-call spelling). The kind cannot be read through the pointer. }
  mk := @MakeSA;
  sa := mk();
  Chk('9 static := indirect call result', sa[1], 8);

  { ---- the remaining right-hand-side kinds the census counted ---- }

  { 10: Copy of a dynamic array. }
  d := Copy(e);
  Chk('10 dyn := Copy(dyn)', d[1], 5);

  { 11: an array constructor. }
  d := [31, 32];
  Chk('11 dyn := array ctor', d[0] + d[1], 63);

  { 12: the splice Concat/`+` builds. }
  d := Concat(e, e);
  Chk('12 dyn := concat', Length(d), 6);

  { 13: a whole-array FIELD destination, both the static and the dynamic
    spelling. Two of the four the defect was reported in. }
  c := TC.Create;
  c.SA := sb;
  Chk('13a class field := static', c.SA[1], 2);
  c.DA := e;
  Chk('13b class dyn field := dyn', c.DA[2], 6);
  c.Free;

  i := 0;
  if fails = 0 then i := 1;
  WriteLn('fails=', fails);
  if i = 1 then WriteLn('WHOLEARRSHAPES OK');
end.
