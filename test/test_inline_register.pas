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

procedure TestCdecl; cdecl;
begin
  writeln('Cdecl test: OK');
end;

procedure TestMultiple; Inline; Register; Cdecl;
begin
  writeln('Multiple test: OK');
end;

begin
  TestInline;
  TestRegister;
  TestBoth;
  TestBothUpper;
  TestCdecl;
  TestMultiple;
  writeln('all inline/register tests completed!');
end.
