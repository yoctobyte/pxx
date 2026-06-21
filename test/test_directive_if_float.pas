program TestDirectiveIfFloat;

{$mode objfpc}

{ Float literals in a conditional expression are a clear error, never
  mis-evaluated. Compile must fail. }
{$if PXX_VERSION >= 14.2}
const Bad = 1;
{$endif}

begin
  writeln(0);
end.
