{ Regression for the scalar-string managed-default flip (string-model slice 4p2).
  Under PXX_MANAGED_STRING (the default) a bare `string` is a managed AnsiString.
  The crash this guards against: a managed `array of string` element assigned into
  a scalar `string` used to be miscompiled as a frozen inline copy and segfaulted
  (bug-managed-to-frozen-string-assign-crash). Also covers frozen string[N] <->
  managed interop both directions. }
program test_managed_string_flip;
var
  a: array of string;     { elements are managed AnsiString }
  s: string;              { scalar string -> managed AnsiString }
  fx: string[31];         { frozen fixed string (word-prefix) }
  pf: ^string[31];
begin
  { 1. managed array element -> scalar managed (the original crash repro). }
  SetLength(a, 1);
  a[0] := 'hello world long enough';
  s := a[0];
  writeln(s);

  { 2. managed -> managed reassign, then concat. }
  s := s + '!';
  writeln(s);

  { 3. frozen fixed string <- managed (coerce into inline buffer). }
  fx := s;
  writeln(fx);

  { 4. managed <- frozen fixed string (materialise into a managed handle). }
  s := fx;
  writeln(s);

  { 5. managed <- frozen fixed string via pointer deref (the deref-assign path). }
  pf := @fx;
  s := pf^;
  writeln(s);
end.
