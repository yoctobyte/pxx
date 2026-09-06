{ `L.Objects[i].Free` and `b.Pick(i).Free` were refused with

    error: "Free": no such member on this record/class

  while `b.FA[i].Free` on the same objects compiled — a message about member
  lookup for a defect about EVALUATION, so the text pointed away from the cause.
  fcl-passrc's pscanner.pp does it twice (`:2729`, `:2899`,
  `FStreams.Objects[i].Free`), and it is everyday Pascal.

  The boundary was BuiltinFreeHere's `PureDesignator(node)` guard, and THE GUARD
  WAS NOT THE BUG. GenMakeFreeObjectExpr puts the operand in three positions —
  nil test, Destroy receiver, FreeMem argument — and the AST is a tree, not a
  DAG, so each is a CloneAST. Deleting the guard alone would have turned a
  refusal into a SILENTLY WRONG PROGRAM: three getter calls, and for a function
  receiver three different objects created and only the last one freed. The fix
  is to materialise a non-designator receiver into a hidden local first.

  SO THE COUNTER IS THE POINT OF THIS TEST AND `freed` ALONE WOULD NOT SEE IT.
  Both getters increment FCalls, and both rows assert that it moved by exactly
  ONE. With the receiver cloned three times the objects still get freed and
  `freed` still reaches 6 — the sum is right and the evaluation count is not —
  so a test that only checked the destructor totals would pass on the broken
  desugaring. Expected values come from fpc 3.2.2 -Mobjfpc.

  The first row is the control from the other direction: an array-element
  receiver is a pure designator, takes no temp, and calls no getter at all
  (calls=0). It is the row that compiled before and must keep its behaviour.
  bug-p-free-on-a-computed-receiver-is-refused-because-the-desugaring-clones-it }
{$mode objfpc}
program test_free_on_a_computed_receiver_evaluates_it_once;
type
  TObj = class
    N: Integer;
    destructor Destroy; override;
  end;
  TBox = class
  private
    FA: array of TObj;
    FCalls: Integer;
    function GetObj(i: Integer): TObj;
  public
    property Objects[i: Integer]: TObj read GetObj;
    function Pick(i: Integer): TObj;
    procedure Fill;
    property Calls: Integer read FCalls;
  end;

var freed: Integer = 0;

destructor TObj.Destroy;
begin
  freed := freed + N;
  inherited Destroy;
end;

function TBox.GetObj(i: Integer): TObj;
begin
  Inc(FCalls);
  Result := FA[i];
end;

function TBox.Pick(i: Integer): TObj;
begin
  Inc(FCalls);
  Result := FA[i];
end;

procedure TBox.Fill;
var i: Integer;
begin
  SetLength(FA, 3);
  for i := 0 to 2 do
  begin
    FA[i] := TObj.Create;
    FA[i].N := i + 1;
  end;
end;

var b: TBox;
begin
  b := TBox.Create;
  b.Fill;
  b.FA[0].Free;       WriteLn('field elem  freed=', freed, ' calls=', b.Calls);
  b.Pick(1).Free;     WriteLn('call        freed=', freed, ' calls=', b.Calls);
  b.Objects[2].Free;  WriteLn('property    freed=', freed, ' calls=', b.Calls);
end.
