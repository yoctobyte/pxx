{ A managed function result DISCARDED at statement level must still be released.

  Extended syntax lets a function be called as a statement. The result is a
  fresh handle with a +1 count that nobody stores, so nothing ever releases it:
  `MkS(i);` in a 1000-trip loop leaked 979 handles, `MkArr(i);` leaked 1968,
  while FPC reports 0 unfreed blocks for both.

  The NilPy arm of this bug was fixed (bug-nilpy-discarded-string-result-leaks)
  and the Pascal sibling was left standing behind a `PyProgramMode` gate, on the
  stated premise that "Pascal has no value-discarding expression statement".

  Every statement-body context is covered here because the first repair only
  reached the ones that funnel through AN_BLOCK / the AN_SEQ spine: a loop body
  that is a BARE statement is neither, so `for .. do MkS(i);` still leaked after
  `for .. do begin MkS(i); end;` was clean. Same coverage hole, one construct
  over, as the AN_IF-arm flush ticket.
  bug-a-a-discarded-managed-function-result-is-never-released }
program test_discarded_managed_result_leaks;
{$mode objfpc}{$H+}
uses sysutils;
type
  TArr = array of AnsiString;
var i, sink: Integer; b: Boolean; guard: AnsiString;
function MkS(n: Integer): AnsiString;
begin MkS := 's' + IntToStr(n); end;
function MkArr(n: Integer): TArr;
begin SetLength(MkArr, 2); MkArr[0] := 'a' + IntToStr(n); MkArr[1] := 'b'; end;
begin
  sink := 0; b := True;

  { bare loop bodies — the shape the first repair missed }
  for i := 1 to 200 do MkS(i);
  for i := 1 to 200 do MkArr(i);

  { block body }
  for i := 1 to 200 do begin MkS(i); end;

  { if / else arms }
  for i := 1 to 200 do if b then MkS(i);
  for i := 1 to 200 do if not b then sink := 0 else MkS(i);

  { case arms, both the value clause and the else clause }
  for i := 1 to 200 do case i mod 2 of 0: MkS(i); else MkS(i); end;

  { while / repeat }
  i := 0; while i < 200 do begin Inc(i); MkS(i); end;
  i := 0; repeat Inc(i); MkS(i); until i >= 200;

  { try body, finally body, except arm }
  for i := 1 to 200 do try MkS(i); except end;
  for i := 1 to 200 do try sink := sink; finally MkS(i); end;
  for i := 1 to 200 do try raise Exception.Create('e'); except MkS(i); end;

  { A USED result must keep working — the park must not consume the value. }
  for i := 1 to 200 do Inc(sink, Length(MkS(i)));
  guard := MkS(7);
  if guard <> 's7' then begin WriteLn('FAIL: used result corrupted: ', guard); Halt(1); end;
  if sink <> 692 then begin WriteLn('FAIL: sink=', sink, ' expected 692'); Halt(1); end;

  WriteLn('ok sink=', sink, ' guard=', guard);
end.
