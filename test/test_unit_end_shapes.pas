program test_unit_end_shapes;
{ The zero-diagnostic fixture for
  bug-p-a-stray-end-at-unit-implementation-top-level-is-silently-skipped: two
  units between them covering every legitimate `end` shape an implementation
  section can present. It asserts VALUES rather than merely compiling, so a
  future arm that swallows a real `end` again cannot pass it by accident. }
uses unit_end_shapes_a, unit_end_shapes_b;

var c: TCounter; fail: Integer;
begin
  fail := 0;
  if ShapesTotal <> 16 then begin WriteLn('ShapesTotal=', ShapesTotal, ' want 16'); fail := fail + 1; end;
  if ShapesBValue <> 32 then begin WriteLn('ShapesBValue=', ShapesBValue, ' want 32'); fail := fail + 1; end;
  c := TCounter.Create;
  c.Bump; c.Bump;
  if c.Value <> 2 then begin WriteLn('Bump=', c.Value, ' want 2'); fail := fail + 1; end;
  if c.Describe(1) <> 'pos!' then begin WriteLn('Describe(1)=', c.Describe(1)); fail := fail + 1; end;
  if c.Describe(0) <> 'nonpos!' then begin WriteLn('Describe(0)=', c.Describe(0)); fail := fail + 1; end;
  c.Free;
  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('ENDSHAPES OK') else WriteLn('ENDSHAPES BAD');
end.
