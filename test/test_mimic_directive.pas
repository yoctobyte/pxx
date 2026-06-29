{$MIMIC FPC}
program test_mimic_directive;

{ {$MIMIC FPC} source directive — equivalent to --mimic-fpc, pinned in the source
  so a project carries its own compatibility need. Applied at lex time, so the
  defines are live for the {$IF} below. Output: "fpc 3.x" + "version=3.2.2". }

begin
{$ifdef FPC}
  {$if FPC_FULLVERSION >= 30000}
  WriteLn('fpc 3.x');
  {$else}
  WriteLn('fpc old');
  {$endif}
  {$if (FPC_VERSION = 3) and (FPC_RELEASE = 2) and (FPC_PATCH = 2)}
  WriteLn('version=3.2.2');
  {$else}
  WriteLn('version mismatch');
  {$endif}
{$else}
  WriteLn('no fpc');
{$endif}
end.
