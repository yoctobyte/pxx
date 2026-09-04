program test_uses_in_explicit_file;
{ `uses <unit> in '<file>'` -- the Delphi/FPC spelling for naming a unit's
  source file, and the one every real .dpr writes. Three entries, taking
  different arms:

    bare name        the .dpr form; resolves against THIS file's own directory
    path + separator must NOT be re-prefixed with ./
    qualified use    the declared name works as a QUALIFIER, which is where the
                     binding is observable rather than inferred from the flat
                     lookup that would answer either way

  Every row is a VALUE and the multipliers are distinct (2/3/5), so an entry
  resolving to the wrong unit is a wrong number rather than a still-plausible
  one.

  WHAT THIS FILE DELIBERATELY DOES NOT CONTAIN: an entry whose declared name
  differs from the unit's own. pxx accepts that and FPC does not -- but FPC
  rejects it for its own reason (a unit's name must match its file's name at
  all, `in` or no `in`), tempered by a DOS-era tolerance that accepts any
  mismatched name of 8 characters or fewer. Measured: `SomeName` accepted,
  `SomeNameXX` rejected, the exact name accepted, on one unchanged file. That
  is a length artifact rather than a rule, no valid FPC source contains the
  shape, and pinning our behaviour against it would be pinning it to the
  artifact. Us accepting what FPC rejects is not a defect, so it is left
  unasserted rather than frozen.

  All three rows here measured byte-identical to FPC 3.2.2 on this file.
  feature-p-uses-a-unit-in-an-explicit-file }
uses
  unit_uses_in_bare in 'unit_uses_in_bare.pas',
  mymod_in in 'uses_in_units/mymod_in.pas',
  othername_in in 'uses_in_units/othername_in.pas';

var fail: Integer;
begin
  fail := 0;
  if BareTwice(21) <> 42 then begin WriteLn('BareTwice=', BareTwice(21), ' want 42'); fail := fail + 1; end;
  if PathThrice(14) <> 42 then begin WriteLn('PathThrice=', PathThrice(14), ' want 42'); fail := fail + 1; end;
  if OtherFive(9) <> 45 then begin WriteLn('OtherFive=', OtherFive(9), ' want 45'); fail := fail + 1; end;
  if othername_in.OtherFive(8) <> 40 then
  begin WriteLn('othername_in.OtherFive=', othername_in.OtherFive(8), ' want 40'); fail := fail + 1; end;
  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('USESIN OK') else WriteLn('USESIN BAD');
end.
