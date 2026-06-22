program test_mimic_fpc;

{ --mimic-fpc CLI flag. No directive in the source: a plain compile must NOT see
  FPC (PXX deliberately does not predefine it); compiling with --mimic-fpc
  installs the curated FPC 3.2.2 define set so identity probes pick the FPC path,
  including the valued FPC_FULLVERSION the numeric {$IF} evaluator reads.
  Output: plain compile -> "fpc=no"; --mimic-fpc -> "fpc=yes / ver>=20400 / unix". }

begin
{$ifdef FPC}
  WriteLn('fpc=yes');
  {$if FPC_FULLVERSION >= 20400}
  WriteLn('ver>=20400');
  {$else}
  WriteLn('ver<20400');
  {$endif}
  {$ifdef UNIX}
  WriteLn('unix');
  {$endif}
{$else}
  WriteLn('fpc=no');
{$endif}
end.
