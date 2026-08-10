{ A `^`/`[` SELECTOR after a function call used as a STATEMENT was silently
  DROPPED — the sibling of test_stmt_call_result_selector_b318, which fixed the
  `.` arm only.

  `Slot(0)^ := 111;` emitted the call and then skipped `^ := 111` to the next
  ';' with NO diagnostic: the store simply never happened. Reading the same
  shape (`Slot(2)^` in an expression) was always correct, and so was
  `t := Slot(1); t^ := 222`, so only the lvalue arm of the double case was
  broken. Found by Track B writing crtl's atexit: every handler slot stored 0
  and the drain jumped to address 0, three frames from the mistake.

  ParseStatementAST's call-result-selector branch now treats `^` and `[` as
  selectors exactly like `.`. Verified against FPC. }
program test_stmt_call_result_deref_b387;
{$mode objfpc}{$h+}
type
  PInt32 = ^Integer;
  TRec = record A, B: Integer; end;
  PRec = ^TRec;
  TArr = array[0..3] of Integer;
  PArr = ^TArr;
var
  buf: array[0..7] of Integer;
  rec: TRec;
  arr: TArr;
  base: Pointer;
  t: PInt32;

function Slot(i: Integer): PInt32;
begin
  Slot := PInt32(NativeInt(base) + i * SizeOf(Integer));
end;

function RecP: PRec;
begin
  RecP := @rec;
end;

function ArrP: PArr;
begin
  ArrP := @arr;
end;

begin
  base := @buf[0];
  Slot(0)^ := 111;                    { write through a call result }
  WriteLn('a=', buf[0]);
  t := Slot(1); t^ := 222;            { via a variable — always worked }
  WriteLn('b=', buf[1]);
  buf[2] := 333;
  WriteLn('c=', Slot(2)^);            { read position — always worked }
  RecP^.A := 44;                      { paramless callee, deref then field }
  WriteLn('d=', rec.A);
  ArrP^[1] := 55;                     { paramless callee, deref then index }
  WriteLn('e=', arr[1]);
  Slot(3)^ := Slot(0)^ + 1;           { call result on BOTH sides }
  WriteLn('f=', buf[3]);
end.
