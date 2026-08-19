{$asmMode default}
program test_asmmode_tolerance;
{ FPC accepts default/att/intel/direct and treats {$asmMode} as a per-file
  assembler-reader selection. Refusing a non-intel value AT THE DIRECTIVE is
  pure conformance loss when the unit holds no asm at all — which is the common
  case, since the directive is written defensively at the top of a file
  (cutils.pas, and every FPC compiler unit after it).
  feature-pascal-asmmode-directive-tolerance }
begin
  WriteLn('asmmode ok');
end.
