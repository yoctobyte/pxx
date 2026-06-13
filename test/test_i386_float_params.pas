program test_i386_float_params;

function CheckMix(a: Integer; b: Double; c: Integer): Integer;
begin
  if (a = 3) and (b > 2.49) and (b < 2.51) and (c = 7) then
    CheckMix := 1
  else
    CheckMix := 0;
end;

begin
  writeln(CheckMix(3, 2.5, 7));
end.
