program test_generic_cross_unit_inline_specialize;
{ objfpc arm of bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized:
  an inline `specialize TSack<LongInt>` in a non-binder position, on a template
  that lives in a used unit. Expected values are FPC 3.2.2's. }
{$MODE OBJFPC}

uses ugdgobj;

var
  s: specialize TSack<LongInt>;
begin
  s := specialize TSack<LongInt>.Create;
  s.Val := 33;
  if s.Val = 33 then writeln('ok   inline specialize, cross-unit')
  else writeln('FAIL inline specialize, cross-unit = ', s.Val);
  writeln('total ok 1 / 1');
end.
