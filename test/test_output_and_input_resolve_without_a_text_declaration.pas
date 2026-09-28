{ `WriteLn(Output, x)` and `ReadLn(Input, x)` are standard Pascal and need no
  declaration: FPC's System declares both files. The Text RTL that declares
  them here was only loaded when the source named `Text`, `TextFile`, `file`,
  `IOResult` or `Flush`, so without one of those this program was refused as
  "undefined variable (Output)". Nothing below names any of them. Expected
  output is FPC 3.2.2's. }
program test_output_and_input_resolve_without_a_text_declaration;
var
  x: Integer;
begin
  ReadLn(Input, x);
  Write(Output, 'twice: ');
  WriteLn(Output, x * 2);
  WriteLn(Output);
  WriteLn('plain');
end.
