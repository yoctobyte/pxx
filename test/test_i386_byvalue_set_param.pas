program test_i386_byvalue_set_param;

type
  TFlag = (fa, fb, fc, fd, fe);
  TFlags = set of TFlag;

function Score(Flags: TFlags; Tail: Integer): Integer;
begin
  if (fa in Flags) and (fc in Flags) and not (fb in Flags) and
     (fe in Flags) and (Tail = 7) then
    Score := 42
  else
    Score := 1;
end;

begin
  writeln(Score([fa, fc, fe], 7));
end.
