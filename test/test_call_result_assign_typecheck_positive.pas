{ A call RESULT is a typed side of an assignment, and the legal shapes must stay
  legal. The refusal half is test_call_result_assign_typecheck_fail.pas; this is
  the half that guards against the fix being one shape too wide, which is the
  real risk when a type check gains a new node kind -- a false REJECT of working
  code is worse than the false accept it was added for.
  Every row runs under fpc 3.2.2 too and .expected IS fpc's own output.
  bug-p-a-string-function-result-assigned-to-an-integer-compiles-silently }
program test_call_result_assign_typecheck_positive;
type TR = record a, b: Integer; end;
     TDyn = array of Integer;
function FStr(const s: AnsiString): AnsiString; begin Result := s + '!'; end;
function FInt: Integer; begin Result := 7; end;
function FChar: Char; begin Result := 'z'; end;
function FRec: TR; begin Result.a := 1; Result.b := 2; end;
function FDyn: TDyn; begin SetLength(Result, 3); Result[0] := 9; end;
function FDbl: Double; begin Result := 1.5; end;
var i: Integer; d: Double; s: AnsiString; c: Char; r: TR; dy: TDyn; i64: Int64;
begin
  i := FInt;       WriteLn('int<-int ', i);
  d := FInt;       WriteLn('dbl<-int ', d:0:1);
  d := FDbl;       WriteLn('dbl<-dbl ', d:0:1);
  i64 := FInt;     WriteLn('i64<-int ', i64);
  s := FStr('a');  WriteLn('str<-str ', s);
  s := FChar;      WriteLn('str<-chr ', s);
  c := FChar;      WriteLn('chr<-chr ', c);
  r := FRec;       WriteLn('rec<-rec ', r.a, r.b);
  dy := FDyn;      WriteLn('dyn<-dyn ', dy[0]);
  WriteLn('controls done');
end.
