program test_index_a_dynamic_array_call_result;
{ `f(...)[i]` where f returns a DYNAMIC array — every spelling of the call.

  The fixed-array half landed long ago; the dynamic half was refused, and the
  two recorded reasons for refusing it were both about the wrong end of the
  problem: they tried to make IRLowerAddress answer an address for the CALL
  node, which is a handle and not a slot. Nothing has to. A dyn-array LOCAL is a
  slot holding a handle, `tmp := call` is an ordinary dyn-array assignment and
  `tmp[i]` an ordinary dyn-array index, so materialising the temp in the PARSER
  — where the fixed arm already materialises its shaped temp — needs no IR
  change at all.

  Every receiver spelling is asserted because they reached three DIFFERENT raw
  AN_INDEX sites, and two of them had quietly stopped refusing: `b.Arr[1]`
  printed 100663296 (0x06000000) and `TBag.Create.Arr[0]` printed 25769803781
  (0x600000005 — elements 0 and 1 read as one 8-byte word). A silent wrong value
  where the pinned compiler still said IR_UNSUPPORTED, which is the trade this
  whole ticket exists to refuse.

  The loop row is the lifetime assertion: the temp is an ordinary scope local
  and gets the ordinary dyn-array release. 200k iterations of the same
  expression hold RSS at 392 kB.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}{$H+}

type
  TIntArr = array of Integer;
  TStrArr = array of string;
  TPt = record X, Y: Integer; end;
  TPtArr = array of TPt;
  TBag = class
  public
    function Arr: TIntArr; virtual;
    function ArrP(k: Integer): TIntArr;
  end;
  TSub = class(TBag)
  public
    function Arr: TIntArr; override;
  end;

function TBag.Arr: TIntArr;
begin SetLength(Result, 3); Result[0] := 5; Result[1] := 6; Result[2] := 7; end;
function TSub.Arr: TIntArr;
begin SetLength(Result, 3); Result[0] := 50; Result[1] := 60; Result[2] := 70; end;
function TBag.ArrP(k: Integer): TIntArr;
begin SetLength(Result, 3); Result[0] := k; Result[1] := k * 2; Result[2] := k * 3; end;

function MakeArr: TIntArr;
begin SetLength(Result, 3); Result[0] := 10; Result[1] := 20; Result[2] := 30; end;
function MakeStr: TStrArr;
begin SetLength(Result, 2); Result[0] := 'alpha'; Result[1] := 'beta'; end;
function MakePt: TPtArr;
begin SetLength(Result, 2);
  Result[0].X := 1; Result[0].Y := 2; Result[1].X := 3; Result[1].Y := 4; end;

var
  b: TBag; v: TBag; i, acc: Integer; cp: TIntArr;
begin
  b := TBag.Create;
  v := TSub.Create;

  { the unqualified call }
  WriteLn('plain  : ', MakeArr[0], ' ', MakeArr[1], ' ', MakeArr[2]);
  { a method on an instance — reached through the lvalue suffix loop }
  WriteLn('method : ', b.Arr[1]);
  { …with arguments, so the call is not a bare name }
  WriteLn('margs  : ', b.ArrP(3)[0], ' ', b.ArrP(3)[2]);
  { …dispatched VIRTUALLY, so the node is AN_VIRTUAL_CALL and not AN_CALL }
  WriteLn('virtual: ', v.Arr[2]);
  { a construction then a method — reached through the chained selector loop }
  WriteLn('inline : ', TBag.Create.Arr[0]);
  { a managed element: the temp must carry the string, not its handle }
  WriteLn('strelem: ', MakeStr[1]);
  { a RECORD element, then a field on it }
  WriteLn('recelem: ', MakePt[1].X, ' ', MakePt[1].Y);
  { the call is evaluated exactly once per subscript, and the temp is released }
  acc := 0;
  for i := 1 to 5 do acc := acc + MakeArr[1];
  WriteLn('loop   : ', acc);

  { the shapes that already worked and must keep working }
  WriteLn('length : ', Length(MakeArr));
  { Copy of a call result, through a variable. Indexing the Copy INTRINSIC's
    result directly — `Copy(MakeArr, 1, 2)[0]` — is a separate shape and is
    still a parse error; it is loud, so it stays out of this test rather than
    being asserted as working. }
  cp := Copy(MakeArr, 1, 2);
  WriteLn('copy   : ', cp[0], ' ', cp[1]);

  b.Free; v.Free;
end.
