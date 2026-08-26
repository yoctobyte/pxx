program test_hidden_dynarray_temp_zeroinit;

{ The SIBLINGS of the for-in-over-a-member-access temp. The Pascal parser
  materialises a hidden UNNAMED dyn-array local at three places, all of them
  during the body's parse — after the prologue's managed-local zero-init pass
  has already run:

    pasparser_stmt.inc  ParseForInNodeAST   `for x in MakeArr`   (a call result)
    pasparser_lval.inc  ApplyCallResultPtrSuffix  `MakeArr[0]`
    pasparser_stmt.inc  the array-constructor arm  `for x in [a, b]`

  Each one's first store RELEASES whatever the slot held, so with a live pointer
  left in the frame all three free a block nobody freed. Fixing the fourth shape
  (for-in over `obj.Items`) in the frontend alone would have left these; the fix
  is the shared late-mint zero-init, so they come green together — which is the
  point of grepping for the sibling before closing the ticket
  (devdocs/dev/normalise-dont-special-case.md).

  This is a CRASH witness: reverted, it SIGSEGVs on all five targets, not just
  the one whose frame layout happens to expose it. }
type
  TItem = class
    Id: Integer;
  end;
  TArr = array of TItem;

var gA, gB: TItem;

function MakeArr: TArr;
begin
  SetLength(Result, 2);
  Result[0] := gA; Result[1] := gB;
end;

procedure DirtyFrame(p: TItem);
var q0,q1,q2,q3,q4,q5,q6,q7: Pointer;
begin
  q0 := Pointer(p); q1 := Pointer(p); q2 := Pointer(p); q3 := Pointer(p);
  q4 := Pointer(p); q5 := Pointer(p); q6 := Pointer(p); q7 := Pointer(p);
  if q0 = nil then Writeln('x');
  if q1 = nil then Writeln('x');
  if q2 = nil then Writeln('x');
  if q3 = nil then Writeln('x');
  if q4 = nil then Writeln('x');
  if q5 = nil then Writeln('x');
  if q6 = nil then Writeln('x');
  if q7 = nil then Writeln('x');
end;

function SumCallResult: Integer;   { for-in over a CALL result (pasparser_stmt:1198) }
var it: TItem;
begin
  Result := 0;
  for it in MakeArr do Result := Result + it.Id;
end;

function IndexCallResult: Integer; { index a call result (pasparser_lval:4648) }
begin
  Result := MakeArr[0].Id + MakeArr[1].Id;
end;

function SumCtor: Integer;         { for-in over an array constructor (pasparser_stmt:2352) }
var it: TItem;
begin
  Result := 0;
  for it in [gA, gB] do Result := Result + it.Id;
end;

begin
  gA := TItem.Create; gA.Id := 30;
  gB := TItem.Create; gB.Id := 12;
  DirtyFrame(gA); Writeln(SumCallResult);
  DirtyFrame(gB); Writeln(IndexCallResult);
  DirtyFrame(gA); Writeln(SumCtor);
  Writeln(gA.Id, ' ', gB.Id);
end.
