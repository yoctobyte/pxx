program TestDirectiveIfTypeMix;

{$mode objfpc}

{ Mixing an integer operand into a boolean operator is a loud error, not a
  silent coercion. Compile must fail. }
{$if 5 and defined(PXX)}
const Bad = 1;
{$endif}

begin
  writeln(0);
end.
