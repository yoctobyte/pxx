program test_inline_register;

procedure TestInline; inline;
begin
  writeln('Inline test: OK');
end;

procedure TestRegister; register;
begin
  writeln('Register test: OK');
end;

procedure TestBoth; Inline; Register;
begin
  writeln('Both test: OK');
end;

procedure TestBothUpper; INLINE; REGISTER;
begin
  writeln('Both upper test: OK');
end;

begin
  TestInline;
  TestRegister;
  TestBoth;
  TestBothUpper;
  writeln('all inline/register tests completed!');
end.
