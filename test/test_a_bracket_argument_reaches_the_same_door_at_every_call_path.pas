program test_a_bracket_argument_reaches_the_same_door_at_every_call_path;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
uses variants;
{ bug-p-the-bracket-argument-door-is-hand-written-at-every-call-path

  `[1, 2, x]` at an argument position is a SET to the grammar and an open-array
  or `array of const` LITERAL to the callee, and only the PARAMETER can say
  which. That question was asked and answered by hand at every call path, and
  each copy was found separately, by a corpus, months apart -- because the wrong
  parse is SILENT: a one-character string or an integer is a legal set item, so
  the call compiles and the callee reads its length out of a set descriptor.

  EVERY ROW ASSERTS A VALUE, NOT A LENGTH, AND THAT IS THE POINT OF THE FILE.
  Length(A) is the same number for a correct open array and for a TVarRec vector
  of the same arity, so a length row passes while the elements are garbage -- the
  `array of Variant` constructor row below did exactly that before 2026-09-06:
  n=3 with three EMPTY values. Only summing or printing the elements separates a
  correct parse from a plausible one.

  Both spellings of every shape live in this ONE file, deliberately: two files
  each printing a plausible number both pass, and two numbers on adjacent lines
  of one output disagree. }
type
  TArr = array of Integer;

  TC = class
    S: Integer;
    constructor Create(const A: array of Integer);
    constructor CreateV(const A: array of const);
    constructor CreateVar(const A: array of Variant);
    procedure M(const A: array of Integer);
    procedure MV(const A: array of Variant);
    procedure Bare(const A: array of Integer);
    procedure CallsBare;
    class procedure CM(const A: array of Integer);
    function Chain: TC;
  end;
  TCClass = class of TC;

  TR = record
    procedure RM(const A: array of Integer);
  end;

  TCb = procedure(const A: array of Integer);

var
  fails: Integer;
  lastSum: Integer;

procedure Check(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

function SumVar(const A: array of Variant): Integer;
{ VALUES, not Length. An `array of Variant` parameter was excluded from the
  open-array arm from the feature's first commit, so `[11, 22, 33]` reached
  whichever wrong answer the call path held: a set descriptor read as a length
  on the method doors, and on the constructor door a TVarRec vector with the
  right COUNT and three EMPTY elements. The count is why it survived -- it is
  the same number either way. }
var i: Integer;
begin
  SumVar := 0;
  for i := 0 to High(A) do SumVar := SumVar + Integer(A[i]);
end;

function SumOf(const A: array of Integer): Integer;
var i: Integer;
begin
  SumOf := 0;
  for i := 0 to High(A) do SumOf := SumOf + A[i];
end;

{ ---- free routine, expression position and statement position ---- }
function FreeFn(const A: array of Integer): Integer;
begin
  FreeFn := SumOf(A);
end;

procedure FreeProc(const A: array of Integer);
begin
  lastSum := SumOf(A);
end;

{ ---- array of const, so the OTHER arm of the same door is exercised ---- }
function CountConst(const A: array of const): Integer;
begin
  CountConst := Length(A);
end;

constructor TC.Create(const A: array of Integer);
begin
  S := SumOf(A);
end;

constructor TC.CreateV(const A: array of const);
begin
  S := Length(A);
end;

constructor TC.CreateVar(const A: array of Variant);
begin
  S := SumVar(A);
end;

procedure TC.M(const A: array of Integer);
begin
  lastSum := SumOf(A);
end;

procedure TC.MV(const A: array of Variant);
begin
  lastSum := SumVar(A);
end;

procedure TC.Bare(const A: array of Integer);
begin
  lastSum := SumOf(A);
end;

procedure TC.CallsBare;
begin
  { the IMPLICIT-SELF bare method call -- `Bare(...)` with no receiver written.
    This path hand-rolled its own argument loop with a bare ParseExpr and asked
    the bracket question of nobody at all until 2026-09-06, so the qualified
    spelling `Self.Bare([...])` was right and the bare one silently was not. }
  Bare([10, 20, 30]);
end;

class procedure TC.CM(const A: array of Integer);
begin
  lastSum := SumOf(A);
end;

function TC.Chain: TC;
begin
  Chain := Self;
end;

procedure TR.RM(const A: array of Integer);
begin
  lastSum := SumOf(A);
end;

var
  o: TC;
  r: TR;
  cb: TCb;
  cref: TCClass;
begin
  fails := 0;

  { free routine, in an EXPRESSION }
  Check('free routine, expression position', FreeFn([10, 20, 30]), 60);

  { free routine, as a STATEMENT }
  lastSum := 0; FreeProc([10, 20, 30]);
  Check('free routine, statement position', lastSum, 60);

  { the array-of-const arm of the same door }
  Check('array of const, free routine', CountConst([1, 'x', 2.5]), 3);

  { CONSTRUCTOR -- the door that answered WHETHER and not WHICH, so every
    bracket became a TVarRec vector and the callee read it with an Integer
    stride: this row summed to 10 against fpc's 60 until 2026-09-06 }
  o := TC.Create([10, 20, 30]);
  Check('constructor, open array of scalar', o.S, 60);
  o.Free;

  o := TC.CreateV([1, 'x']);
  Check('constructor, array of const', o.S, 2);
  o.Free;

  o := TC.CreateVar([11, 22, 33]);
  Check('constructor, array of Variant', o.S, 66);
  o.Free;

  { METACLASS-dispatched construction -- a different door again }
  cref := TC;
  o := cref.Create([1, 2, 3, 4]);
  Check('metaclass constructor', o.S, 10);

  { instance method }
  lastSum := 0; o.M([10, 20, 30]);
  Check('instance method', lastSum, 60);

  { the IMPLICIT-SELF bare call, and its QUALIFIED twin, in that order }
  lastSum := 0; o.CallsBare;
  Check('implicit-Self bare method call', lastSum, 60);

  { `array of Variant` -- both doors, elements asserted rather than counted }
  lastSum := 0; o.MV([11, 22, 33]);
  Check('array of Variant, instance method', lastSum, 66);

  { instance method reached through a SELECTOR CHAIN }
  lastSum := 0; o.Chain.M([10, 20, 30]);
  Check('method through a selector chain', lastSum, 60);

  { CLASS/static method }
  lastSum := 0; TC.CM([10, 20, 30]);
  Check('class method', lastSum, 60);
  o.Free;

  { RECORD method }
  lastSum := 0; r.RM([10, 20, 30]);
  Check('record method', lastSum, 60);

  { INDIRECT call through a procedural type }
  cb := @FreeProc;
  lastSum := 0; cb([10, 20, 30]);
  Check('indirect call through a procedural type', lastSum, 60);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('BRACKETDOOR OK');
end.
