program test_float_result_loop;
{ Regression for feature-result-in-loop: a Double function that read-modifies
  Result inside a loop must return the accumulated value, not 0. The bug was the
  x86-64 epilogue loading the float Result into xmm0 without bridging to rax (the
  value-model register for a float return); a loop's condition clobbered rax so
  the caller read 0. }

function ViaLoopWhile: Double;   { Result *= 2 three times via while }
var n: Integer;
begin
  Result := 1.0;
  n := 3;
  while n > 0 do begin Result := Result * 2.0; n := n - 1; end;
end;

function ViaLoopFor: Double;     { Result += 1.5 four times via for }
var i: Integer;
begin
  Result := 0.0;
  for i := 1 to 4 do Result := Result + 1.5;
end;

function NoLoop: Double;         { control: no loop }
begin
  Result := 1.0;
  Result := Result * 2.0;
end;

begin
  writeln(ViaLoopWhile:0:4);    { 8.0000 }
  writeln(ViaLoopFor:0:4);      { 6.0000 }
  writeln(NoLoop:0:4);          { 2.0000 }
end.
