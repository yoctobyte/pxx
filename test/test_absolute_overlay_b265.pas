program test_absolute_overlay_b265;
{ `x: T absolute y` — x SHARES y's storage (a classic Pascal overlay).

  `absolute` was not recognised AT ALL. The var-section's "skip qualifiers" loop handed
  `absolute` and the target name to ParseTypeKind, where both fell through the
  unknown-type-name default and quietly became Integers — so the keyword was SILENTLY
  IGNORED and the variable got its own storage instead. Reading it gave 0; writing it
  never touched the target. Wrong values, no diagnostic.

  (That unknown-name default is itself the open bug-pascal-unknown-type-silently-integer —
  this is a second symptom of it, after the TObject/TClass/Int16 truncation family.)

  Aliasing is exactly "same storage": the symbol takes the target's offset. Overlays that
  would cross address spaces (a local onto a global, or a by-ref parameter whose slot
  holds an ADDRESS rather than the value) are REJECTED loudly rather than half-supported. }
var
  a: Integer;
  b: Integer absolute a;        { global overlay }
  i: Integer;
  c: Cardinal absolute i;       { same bytes, different interpretation }

procedure Locals;
var
  x: Integer;
  y: Integer absolute x;        { local overlay }
begin
  x := 7;
  writeln('local=', x, ' ', y);
  y := 11;                      { writing the alias must write the target }
  writeln('local=', x, ' ', y);
end;

begin
  a := 4;
  writeln('global=', a, ' ', b);
  b := 9;
  writeln('global=', a, ' ', b);

  Locals;

  i := -1;
  writeln('reinterp=', c);      { the same bytes read unsigned }
end.
