{ Deliberately carries NO $MODE directive - that is the whole point.

  Real Delphi-targeting projects set the dialect in the build (`-Mdelphi`), not
  in each source file, so their sources look exactly like this one. The Makefile
  compiles it TWICE and the two outputs must differ:

    (no flag)   default objfpc-ish : bare CountDown reads Result   -> 7 1
    -Mdelphi                       : bare CountDown RECURSES       -> 42 4

  If the command-line mode switch is ignored, both runs print 7 1 and the test
  fails — it cannot pass by accident.

  Both expectations measured against FPC 3.2.2 under -Mobjfpc / -Mdelphi.

  NB: this comment contains no brace characters at all, on purpose. Delphi mode
  does not nest comments, so a closing brace anywhere inside a brace comment ends
  it early and the prose after it is parsed as code. The first two drafts of this
  file failed under FPC -Mdelphi for exactly that reason - the second one in the
  very sentence describing the hazard.
  compat-pascal-no-command-line-mode-switch }
program test_pascal_mode_switch_cli;

var
  depth: Integer;

function CountDown: Integer;
begin
  Result := 7;                 { so the objfpc path has a defined value to read }
  Inc(depth);
  if depth < 4 then
    Result := CountDown        { delphi: a recursive call. objfpc: reads Result. }
  else
    Result := 42;
end;

begin
  depth := 0;
  writeln(CountDown);          { objfpc 7  / delphi 42 }
  writeln(depth);              { objfpc 1  / delphi 4  }
end.
