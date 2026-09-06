{ `procedure P(a: array of LongInt)` and `procedure P(a: TDynArr)` are two
  overloads in fpc and were ONE signature here. IsArray is a single bit that is
  True for both, and Params[].TypeKind holds the ELEMENT kind for both, so
  FindProcOverloadRec saw a matching pair: the second declaration was written
  into the first's row, pxx warned `duplicate definition ... the later body
  wins`, and every call to EITHER ran the later body.

  ProcParamDynDepth was never a missing fact. It is a PARTIALLY-CONSULTED one:
  written by every declaration-site parser, read by ir.inc at the call site, and
  ignored by the comparison that decides whether two declarations are the same
  routine. An absence can be found by a set difference; a column one consumer
  reads and another does not cannot be, and the only question that surfaces it
  is "what distinguishes these two, and is that thing consulted where they are
  distinguished".

  ASSERTED BY VALUE AND NOT BY EXIT CODE. The corpus row this came from
  (tarrconstr6.pp) judges by exit code and reaches its Halt only because it was
  written with one; a wrong binding is a wrong-VALUE defect and an exit-clean
  row would have said nothing about the first three cases.

  BOTH DECLARATION ORDERS, and that is the row that earned its place. The first
  version of the fix ranked a dyn-array ARGUMENT away from the open parameter
  and looked complete: every row of the ticket's own repro was correct. Written
  the other way round, `Test([])` and `Test([1,2,3])` answered 2 where fpc
  answers 1 -- the element-list direction still tied and the exact phase took
  whichever candidate came first in the chain. One source order cannot tell a
  rule from an accident of declaration order.

  fpc 3.2.2 is the oracle for every row. `Test(Nil)` is deliberately NOT here:
  fpc binds it to the dynamic overload and we take whichever is declared first,
  which is an open gap recorded on the ticket rather than a row to freeze.
  bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature }
program test_an_open_array_and_a_named_dynamic_array_are_two_overloads;

type
  TLongIntArray = array of LongInt;
  TOther = array of LongInt;

function Test(aArr: array of LongInt): Integer; begin Test := 1 end;
function Test(aArr: TLongIntArray): Integer;    begin Test := 2 end;

{ the SAME pair written the other way round, so no row can pass by sitting
  first in the chain }
function Rev(aArr: TOther): Integer;            begin Rev := 2 end;
function Rev(aArr: array of LongInt): Integer;  begin Rev := 1 end;

{ the control that must NOT be split: a forward and its body are ONE routine,
  and an arm that split on a column a declaration path forgot to write would
  turn this into a phantom overload with no diagnostic at all }
procedure Same(a: TLongIntArray); forward;
procedure Same(a: TLongIntArray); begin Writeln('same len=', Length(a)); end;

{ ...and the everyday case that must keep working: a named dynamic array
  passed to the ONLY candidate, which is an open array. Ranking must not
  become refusing. }
function OnlyOpen(a: array of LongInt): Integer; begin OnlyOpen := Length(a) end;

var
  la: TLongIntArray;
  ot: TOther;

begin
  la := Nil;
  ot := Nil;
  Writeln('fwd empty=', Test([]), ' lit=', Test([1, 2, 3]),
          ' ctor=', Test(TLongIntArray.Create(1, 2, 3)), ' named=', Test(la));
  Writeln('rev empty=', Rev([]), ' lit=', Rev([1, 2, 3]),
          ' ctor=', Rev(TOther.Create(1, 2, 3)), ' named=', Rev(ot));
  SetLength(la, 2);
  Same(la);
  SetLength(la, 4);
  Writeln('only-open candidate=', OnlyOpen(la));
end.
