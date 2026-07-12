program test_ptr_untyped_deref;
{ `Pointer(expr)^` — FPC's untyped deref as an untyped var/const argument
  (synautil's Move(Pointer(Value)^, ...)). The deref is modeled as a Byte
  lvalue; only its address matters to untyped params. }
var
  a, b: array[0..7] of Byte;
  p: Pointer;
  i: Integer;
  ok: Boolean;
begin
  for i := 0 to 7 do begin a[i] := i + 1; b[i] := 0; end;
  p := @a[0];
  Move(Pointer(p)^, b[0], 8);
  ok := True;
  for i := 0 to 7 do if b[i] <> i + 1 then ok := False;
  writeln('move=', ok);
  FillChar(Pointer(p)^, 4, $EE);
  writeln('fill=', (a[0] = $EE) and (a[3] = $EE) and (a[4] = 5));
end.
