program test_p_a_bracket_slot_is_ranked_by_what_its_elements_are;
{$mode objfpc}{$H+}
{ Two plain array overloads at one bracket slot, ranked by the ELEMENTS.

  EVERY SHAPE IS WRITTEN IN BOTH DECLARATION ORDERS, and that is the whole
  design of the file. fpc's answer does not depend on declaration order and ours
  depended on nothing else, so a one-order fixture passes on the order that
  happens to agree and says nothing. Measured 2026-09-09, fpc 3.2.2, a 72-row
  matrix over six candidate pairs x six element lists x both orders.

  THE ROWS THAT MATTER ARE THE ONES THAT USED TO BE REFUSED, not the ones that
  picked a wrong body. With `array of string` declared FIRST,
  `c.P(1, [7, 8])` was `incompatible types: cannot assign Integer to AnsiString`
  -- legal code turned away, and the pinned compiler turns it away too. Arity
  handed the slot to the first-declared candidate and the committed parse then
  bound an integer literal to a string element.

  THE BODIES PRINT A VALUE AND NOT ONLY A NAME. A count is the same number
  whichever body ran, so `sum=` / the joined string is what separates a correct
  pick from a plausible one -- the same reason
  test_p_an_array_of_const_wins_a_bracket_argument sums rather than counts.

  A `set of Byte` CANDIDATE IS HERE TOO, and it is the one row whose answer is
  not about arrays at all: fpc gives the SET the slot whenever the elements are
  ordinal -- even against `array of Integer` -- and takes it away again the
  moment they are not, so `['x', 'yz']` against the same pair runs the string
  array. Both directions are asserted, in both orders.
  THE PARSE SIDE NEEDED NO CHANGE, which is why this could join the array rows
  rather than needing its own coordinated commit: TryParseBracketArgForSlot is
  handed the CHOSEN row, finds neither ParamIsVarRecArray nor
  ParamIsOpenArrayScalar on a set parameter, returns -1, and the argument goes
  to ParseExpr -- which reads `[7, 8]` as the set literal it now is. One row
  decides selection and parsing, so the two cannot disagree.
  bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it

  NOT HERE, DELIBERATELY, AND EACH HAS A REASON:
  - an empty `[]` against two array overloads. fpc REFUSES it ("Can't determine
    which overloaded function to call") and we take the first declared. Us
    accepting what fpc rejects is not a defect, so there is nothing to assert.
  - element lists no candidate can take (`['a']` against Integer/Double). fpc
    refuses; we accept and run something. Also us-accepting-what-fpc-rejects,
    and pre-existing on both sides of this change.

  bug-p-two-non-const-array-overloads-at-a-bracket-slot-cannot-be-ranked-by-element-type }
type
  TByteSet = set of Byte;

  { integer elements vs an integer / string pair, both orders }
  TIntStr = class
    procedure P(N: Integer; A: array of Integer); overload;
    procedure P(N: Integer; A: array of string);  overload;
  end;
  TStrInt = class
    procedure P(N: Integer; A: array of string);  overload;
    procedure P(N: Integer; A: array of Integer); overload;
  end;
  { integer elements vs a WIDE and a NARROW ordinal: fpc takes Integer over Byte }
  TIntByte = class
    procedure P(N: Integer; A: array of Integer); overload;
    procedure P(N: Integer; A: array of Byte);    overload;
  end;
  TByteInt = class
    procedure P(N: Integer; A: array of Byte);    overload;
    procedure P(N: Integer; A: array of Integer); overload;
  end;
  { integer elements vs an integer / float pair, and float elements vs the same }
  TIntDbl = class
    procedure P(N: Integer; A: array of Integer); overload;
    procedure P(N: Integer; A: array of Double);  overload;
  end;
  TDblInt = class
    procedure P(N: Integer; A: array of Double);  overload;
    procedure P(N: Integer; A: array of Integer); overload;
  end;
  { string elements vs a float / string pair -- the float is the first-declared
    one in TDblStr, which is the arrangement that used to win by order }
  TDblStr = class
    procedure P(N: Integer; A: array of Double);  overload;
    procedure P(N: Integer; A: array of string);  overload;
  end;
  TStrDbl = class
    procedure P(N: Integer; A: array of string);  overload;
    procedure P(N: Integer; A: array of Double);  overload;
  end;
  { a SET against an array: ordinal elements give the set the slot, anything
    else takes it away again }
  TIntSet = class
    procedure P(N: Integer; A: array of Integer); overload;
    procedure P(N: Integer; A: TByteSet);         overload;
  end;
  TSetInt = class
    procedure P(N: Integer; A: TByteSet);         overload;
    procedure P(N: Integer; A: array of Integer); overload;
  end;
  TStrSet = class
    procedure P(N: Integer; A: array of string);  overload;
    procedure P(N: Integer; A: TByteSet);         overload;
  end;
  TSetStr = class
    procedure P(N: Integer; A: TByteSet);         overload;
    procedure P(N: Integer; A: array of string);  overload;
  end;

function SumI(const A: array of Integer): Integer;
var i: Integer;
begin SumI := 0; for i := 0 to High(A) do SumI := SumI + A[i]; end;

function SumB(const A: array of Byte): Integer;
var i: Integer;
begin SumB := 0; for i := 0 to High(A) do SumB := SumB + A[i]; end;

function SumD(const A: array of Double): Double;
var i: Integer;
begin SumD := 0; for i := 0 to High(A) do SumD := SumD + A[i]; end;

{ The set body SUMS ITS MEMBERS rather than announcing itself, for the same
  reason every other body here prints a value: `set` alone would pass whether
  the literal reached it as a set or as garbage handed to a set parameter. }
function SumSet(const A: TByteSet): Integer;
var i: Integer;
begin SumSet := 0; for i := 0 to 255 do if i in A then SumSet := SumSet + i; end;

function JoinS(const A: array of string): AnsiString;
var i: Integer;
begin JoinS := ''; for i := 0 to High(A) do JoinS := JoinS + A[i]; end;

procedure TIntStr.P(N: Integer; A: array of Integer); begin WriteLn('intstr  ints sum=', SumI(A)); end;
procedure TIntStr.P(N: Integer; A: array of string);  begin WriteLn('intstr  strs s=', JoinS(A)); end;
procedure TStrInt.P(N: Integer; A: array of string);  begin WriteLn('strint  strs s=', JoinS(A)); end;
procedure TStrInt.P(N: Integer; A: array of Integer); begin WriteLn('strint  ints sum=', SumI(A)); end;

procedure TIntByte.P(N: Integer; A: array of Integer); begin WriteLn('intbyte ints sum=', SumI(A)); end;
procedure TIntByte.P(N: Integer; A: array of Byte);    begin WriteLn('intbyte byts sum=', SumB(A)); end;
procedure TByteInt.P(N: Integer; A: array of Byte);    begin WriteLn('byteint byts sum=', SumB(A)); end;
procedure TByteInt.P(N: Integer; A: array of Integer); begin WriteLn('byteint ints sum=', SumI(A)); end;

procedure TIntDbl.P(N: Integer; A: array of Integer); begin WriteLn('intdbl  ints sum=', SumI(A)); end;
procedure TIntDbl.P(N: Integer; A: array of Double);  begin WriteLn('intdbl  dbls sum=', SumD(A):0:2); end;
procedure TDblInt.P(N: Integer; A: array of Double);  begin WriteLn('dblint  dbls sum=', SumD(A):0:2); end;
procedure TDblInt.P(N: Integer; A: array of Integer); begin WriteLn('dblint  ints sum=', SumI(A)); end;

procedure TDblStr.P(N: Integer; A: array of Double); begin WriteLn('dblstr  dbls sum=', SumD(A):0:2); end;
procedure TDblStr.P(N: Integer; A: array of string); begin WriteLn('dblstr  strs s=', JoinS(A)); end;
procedure TStrDbl.P(N: Integer; A: array of string); begin WriteLn('strdbl  strs s=', JoinS(A)); end;
procedure TStrDbl.P(N: Integer; A: array of Double); begin WriteLn('strdbl  dbls sum=', SumD(A):0:2); end;

procedure TIntSet.P(N: Integer; A: array of Integer); begin WriteLn('intset  ints sum=', SumI(A)); end;
procedure TIntSet.P(N: Integer; A: TByteSet);         begin WriteLn('intset  set  n=', SumSet(A)); end;
procedure TSetInt.P(N: Integer; A: TByteSet);         begin WriteLn('setint  set  n=', SumSet(A)); end;
procedure TSetInt.P(N: Integer; A: array of Integer); begin WriteLn('setint  ints sum=', SumI(A)); end;
procedure TStrSet.P(N: Integer; A: array of string);  begin WriteLn('strset  strs s=', JoinS(A)); end;
procedure TStrSet.P(N: Integer; A: TByteSet);         begin WriteLn('strset  set  n=', SumSet(A)); end;
procedure TSetStr.P(N: Integer; A: TByteSet);         begin WriteLn('setstr  set  n=', SumSet(A)); end;
procedure TSetStr.P(N: Integer; A: array of string);  begin WriteLn('setstr  strs s=', JoinS(A)); end;

var
  a: TIntStr; b: TStrInt; c: TIntByte; d: TByteInt;
  e: TIntDbl; f: TDblInt; g: TDblStr; h: TStrDbl;
  p: TIntSet; q: TSetInt; r: TStrSet; t: TSetStr;
begin
  a := TIntStr.Create; b := TStrInt.Create;
  c := TIntByte.Create; d := TByteInt.Create;
  e := TIntDbl.Create;  f := TDblInt.Create;
  g := TDblStr.Create;  h := TStrDbl.Create;
  p := TIntSet.Create;  q := TSetInt.Create;
  r := TStrSet.Create;  t := TSetStr.Create;

  { integer elements: the integer body, whichever order }
  a.P(1, [7, 8]);
  b.P(1, [7, 8]);          { WAS REFUSED: cannot assign Integer to AnsiString }

  { string elements: the string body, whichever order }
  a.P(1, ['x', 'yz']);
  b.P(1, ['x', 'yz']);

  { integer elements, wide vs narrow ordinal: Integer, not Byte }
  c.P(1, [7, 8]);
  d.P(1, [7, 8]);

  { integer elements against a float candidate: the integer one }
  e.P(1, [7, 8]);
  f.P(1, [7, 8]);

  { float elements: the float body, whichever order }
  e.P(1, [1.5, 2.5]);
  f.P(1, [1.5, 2.5]);

  { string elements against a float candidate: the string one }
  g.P(1, ['x', 'yz']);
  h.P(1, ['x', 'yz']);

  { float elements against a string candidate: the float one }
  g.P(1, [1.5, 2.5]);
  h.P(1, [1.5, 2.5]);      { WAS REFUSED }

  { a SET candidate: ordinal elements take it, string elements do not }
  p.P(1, [7, 8]);
  q.P(1, [7, 8]);
  r.P(1, [7, 8]);
  t.P(1, [7, 8]);
  { ONE-CHARACTER strings, not `['x', 'yz']`, and the difference is measured
    rather than stylistic: against a set candidate fpc REFUSES a multi-character
    string element outright -- "Ordinal expression expected" -- because it reads
    the literal as a set and 'yz' is not a set member. We accept it and run the
    string body, which is us accepting what fpc rejects and therefore not a
    defect, but it is not a row an fpc-oracle fixture may assert.
    This corrects the rule as first written here: "string elements take the
    string array" was generalised from single-character lists, which are the
    only ones that had been measured. }
  r.P(1, ['a', 'b']);
  t.P(1, ['a', 'b']);
end.
