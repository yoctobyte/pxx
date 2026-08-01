{ compat-pascal-const-expr-ord-chr-succ: Ord/Chr/Length/Succ/Pred/Low/High
  must fold in a const declaration, a case label, and an array-bound
  position — FPC/Delphi fold all of these; pxx folded none of them before
  this fix (only bitwise/arithmetic operators and High/Low already worked). }
program TestConstExprBuiltins;

const
  COrd = Ord('q');
  CChr: Char = Chr(65);
  CLen = Length('abcde');
  CSucc = Succ(5);
  CPred = Pred(5);
  CLow = Low(Integer);
  CHigh = High(Byte);

type
  TFixed = array[0..Succ(2)] of Integer;   { array-bound position }

var
  arr: TFixed;
  keyCode: Integer;
  i: Integer;
  ok: Boolean;
begin
  ok := True;
  if COrd <> 113 then ok := False;
  if CChr <> 'A' then ok := False;
  if CLen <> 5 then ok := False;
  if CSucc <> 6 then ok := False;
  if CPred <> 4 then ok := False;
  if CLow <> -2147483648 then ok := False;
  if CHigh <> 255 then ok := False;
  if High(arr) <> 3 then ok := False;   { array[0..3], 4 elements }

  for i := 0 to High(arr) do arr[i] := i;
  if arr[3] <> 3 then ok := False;

  keyCode := Ord('q');
  case keyCode of
    Ord('q'): ;   { case-label position }
  else
    ok := False;
  end;

  if ok then WriteLn('ok') else WriteLn('FAIL');
end.
