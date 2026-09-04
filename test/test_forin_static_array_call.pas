program test_forin_static_array_call;
{$mode objfpc}{$H+}
{ `for x in <call returning a FIXED array>`.

  The sibling of the dyn-array arm that has existed since
  compat-pascal-index-a-function-call-result. Both spellings were refused and
  with DIFFERENT messages -- the bare one died at the container-expression
  dispatch ("not a generator, enum type, or iterable variable") and the
  qualified one got as far as ParseForInNodeAST ("unsupported iterable
  expression"). One gap, two messages, which is why it read as two problems.
  Both now ask NodeIsFixedArrayCallResult, one predicate, so they cannot drift.

  MATERIALISED into a hidden local, and that is correct HERE where it was not
  correct for `for x in p^`: a call result is a temporary nobody else holds, so
  a private copy aliases nothing. The pointee behind a pointer is live storage
  the body can write through, so that arm indexes in place instead. Same
  question, two answers, and the shape decides.

  `calls=1` is the load-bearing row -- it is what "materialise" has to buy, and
  a re-evaluating loop would print 4. `lowbound=` covers a result whose array
  type does not start at 0, which the extent path would get wrong by reading a
  length where it needs a bound.
  bug-p-for-in-over-a-static-array-returning-call-is-refused }
type
  TA  = array[0..3] of Integer;
  TLo = array[2..4] of Integer;
  TR  = record a, b: Integer; end;
  TAR = array[0..2] of TR;
  TObj = class
    fArr: TA;
    function GetArr: TA;
  end;
var
  calls, x: Integer;
  o: TObj;
  r: TR;
function TObj.GetArr: TA; begin Result := fArr; end;
function MkArr: TA;
begin
  Inc(calls);
  MkArr[0] := 1; MkArr[1] := 2; MkArr[2] := 3; MkArr[3] := 4;
end;
function MkLo: TLo;
begin MkLo[2] := 20; MkLo[3] := 30; MkLo[4] := 40; end;
function MkRecs: TAR;
begin
  MkRecs[0].a := 7; MkRecs[1].a := 8; MkRecs[2].a := 9;
end;
begin
  calls := 0;
  Write('bare=');
  for x in MkArr do Write(x, ' ');
  WriteLn;
  WriteLn('calls=', calls);
  o := TObj.Create;
  o.fArr[0] := 5; o.fArr[1] := 6; o.fArr[2] := 7; o.fArr[3] := 8;
  Write('method=');
  for x in o.GetArr do Write(x, ' ');
  WriteLn;
  Write('lowbound=');
  for x in MkLo do Write(x, ' ');
  WriteLn;
  Write('recelem=');
  for r in MkRecs do Write(r.a, ' ');
  WriteLn;
end.
