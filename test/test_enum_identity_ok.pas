{ The enum-identity check must reject cross-enum assignment/compare WITHOUT breaking
  anything legal. Identity is ident-level, so a cast, an Ord(), or a call result is
  deliberately left unchecked — this is a diagnostic, not a type system.

  Guards the false-positive side of test_enum_identity_fail.pas. }
program test_enum_identity_ok;
type
  TColor = (red, green, blue);
  TFruit = (apple, banana, cherry);
var
  c: TColor;
  f: TFruit;
  i: Integer;
  fails: Integer;

procedure Check(const what: AnsiString; got, want: Int64);
begin
  if got = want then writeln('ok   ', what, ' = ', got)
  else
  begin
    writeln('FAIL ', what, ' = ', got, ' (want ', want, ')');
    fails := fails + 1;
  end;
end;

begin
  fails := 0;

  { same enum: assignment and comparison }
  c := blue;
  f := banana;
  Check('same-enum assign (c)', Ord(c), 2);
  Check('same-enum assign (f)', Ord(f), 1);
  Check('same-enum compare', Ord(c = blue), Ord(True));
  Check('same-enum compare (ne)', Ord(c = red), Ord(False));

  { enum -> integer via Ord, and ordinals of DIFFERENT enums compared as integers }
  i := Ord(c);
  Check('Ord(enum)', i, 2);
  Check('Ord vs Ord across enums', Ord(Ord(c) = Ord(cherry)), Ord(True));

  { an explicit cast is the sanctioned way to cross }
  c := TColor(1);
  Check('cast TColor(1)', Ord(c), 1);

  { a call result carries no ident-level identity — unchecked by design }
  c := Succ(red);
  Check('Succ(red)', Ord(c), 1);

  { enum-typed value used as an ordinal }
  Check('Ord arithmetic', Ord(blue) - Ord(red), 2);

  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.
