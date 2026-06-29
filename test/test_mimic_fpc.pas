program test_mimic_fpc;

{ --mimic-fpc CLI flag. No directive in the source: a plain compile must NOT see
  FPC (PXX deliberately does not predefine it); compiling with --mimic-fpc
  installs the curated FPC 3.2.2 define set so identity probes pick the FPC path,
  including the valued FPC_VERSION/FPC_RELEASE/FPC_PATCH/FPC_FULLVERSION defines
  the numeric {$IF} evaluator reads.
  Output: plain compile -> "fpc=no"; --mimic-fpc -> FPC identity + version lines. }

begin
{$ifdef FPC}
  WriteLn('fpc=yes');
  {$if FPC_FULLVERSION >= 20400}
  WriteLn('ver>=20400');
  {$else}
  WriteLn('ver<20400');
  {$endif}
  {$if defined(FPC) and (FPC_VERSION >= 3)}
  WriteLn('major>=3');
  {$else}
  WriteLn('major<3');
  {$endif}
  {$if (FPC_VERSION = 3) and (FPC_RELEASE = 2) and (FPC_PATCH = 2)}
  WriteLn('version=3.2.2');
  {$else}
  WriteLn('version mismatch');
  {$endif}
  {$ifdef UNIX}
  WriteLn('unix');
  {$endif}
{$else}
  WriteLn('fpc=no');
{$endif}
end.
