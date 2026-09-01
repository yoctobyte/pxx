{ A DYNAMIC ARRAY PASSED AS A `var` PARAMETER — read, write, and SetLength.

  riscv32 and xtensa read such a parameter ONE DEREF SHORT. The frame slot of a
  by-ref param holds &caller_slot, and both backends' IR_LEA loaded once (which
  lands on the caller's slot) and used the result as the data pointer. arm32 has
  carried both loads since it was written; x86-64, i386 and aarch64 were right
  too, so this was two backends out of six.

  IT IS A READ BUG BEFORE IT IS A WRITE BUG, which is what kept it invisible:
  `Length(a)` and `a[1]` came back 0 with no crash and no diagnostic. A VALUE or
  CONST parameter was correct on every target — those slots really do hold the
  handle — so a test written with either mode passes on the broken backends.
  That is why the value and const rows below are here beside the var rows: they
  are the ones that were already right, and a change that breaks them is
  breaking something else.

  Writing was worse. `a[3] := 21` through a var param stored through the
  caller's SLOT ADDRESS as if it were the data pointer — writing into the
  caller's stack while leaving the caller's array untouched. examples/sat/
  satdemo.pas and examples/fm/fm.pas both died on the next read (SIGSEGV on
  riscv32, SIGBUS on xtensa); neither crashed anywhere near the store that did
  the damage.

  bug-a-riscv32-and-xtensa-read-a-var-dynamic-array-param-one-deref-short }
program test_dynarray_var_param;

type
  TIntArray = array of Integer;

var
  fails: Integer;

procedure Expect(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL: ', what, ' = ', got, ', want ', want);
    Inc(fails);
  end;
end;

{ READ through each parameter mode. Value and const were always correct; they
  are the control that says this test is still about the by-ref deref. }
procedure ReadVar(var a: TIntArray);
begin
  Expect('var param Length', Length(a), 4);
  Expect('var param High', High(a), 3);
  Expect('var param a[1]', a[1], 99);
end;

procedure ReadValue(a: TIntArray);
begin
  Expect('value param Length', Length(a), 4);
  Expect('value param a[1]', a[1], 99);
end;

procedure ReadConst(const a: TIntArray);
begin
  Expect('const param Length', Length(a), 4);
  Expect('const param a[1]', a[1], 99);
end;

{ WRITE through a var param must reach the CALLER's array, not a copy and not
  the caller's stack. }
procedure WriteThrough(var a: TIntArray);
begin
  a[0] := 11;
  a[3] := 44;
end;

{ SetLength through a var param must republish into the caller's slot, and the
  new length must be visible on both sides. }
procedure GrowIt(var a: TIntArray);
begin
  SetLength(a, 7);
  Expect('after SetLength, inside Length', Length(a), 7);
  a[6] := 66;
end;

var
  m: TIntArray;
begin
  fails := 0;

  SetLength(m, 4);
  m[1] := 99;
  Expect('caller Length before', Length(m), 4);

  ReadVar(m);
  ReadValue(m);
  ReadConst(m);

  WriteThrough(m);
  Expect('caller sees a[0] written through var', m[0], 11);
  Expect('caller sees a[3] written through var', m[3], 44);
  Expect('caller Length unchanged by writes', Length(m), 4);

  GrowIt(m);
  Expect('caller Length after SetLength', Length(m), 7);
  Expect('caller sees a[6] set after grow', m[6], 66);
  Expect('grow preserved a[1]', m[1], 99);

  if fails = 0 then WriteLn('DYNARRAY VAR PARAM OK')
  else begin WriteLn(fails, ' FAILURES'); Halt(1); end;
end.
