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

  NOT HERE, DELIBERATELY, AND EACH HAS A TICKET OR A REASON:
  - a `set of Byte` candidate at the slot. fpc gives the SET the slot for
    ordinal elements even against `array of Integer`; we veto the narrowing
    instead. Matching it changes how the argument is PARSED, not just which
    candidate is named --
    bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it.
  - an empty `[]` against two array overloads. fpc REFUSES it ("Can't determine
    which overloaded function to call") and we take the first declared. Us
    accepting what fpc rejects is not a defect, so there is nothing to assert.
  - element lists no candidate can take (`['a']` against Integer/Double). fpc
    refuses; we accept and run something. Also us-accepting-what-fpc-rejects,
    and pre-existing on both sides of this change.

  bug-p-two-non-const-array-overloads-at-a-bracket-slot-cannot-be-ranked-by-element-type }
type
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

function SumI(const A: array of Integer): Integer;
var i: Integer;
begin SumI := 0; for i := 0 to High(A) do SumI := SumI + A[i]; end;

function SumB(const A: array of Byte): Integer;
var i: Integer;
begin SumB := 0; for i := 0 to High(A) do SumB := SumB + A[i]; end;

function SumD(const A: array of Double): Double;
var i: Integer;
begin SumD := 0; for i := 0 to High(A) do SumD := SumD + A[i]; end;

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

var
  a: TIntStr; b: TStrInt; c: TIntByte; d: TByteInt;
  e: TIntDbl; f: TDblInt; g: TDblStr; h: TStrDbl;
begin
  a := TIntStr.Create; b := TStrInt.Create;
  c := TIntByte.Create; d := TByteInt.Create;
  e := TIntDbl.Create;  f := TDblInt.Create;
  g := TDblStr.Create;  h := TStrDbl.Create;

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
end.
