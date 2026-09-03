program test_open_array_param_aliasing;
{ WHAT A pxx OPEN-ARRAY PARAMETER ALIASES, AND WHAT IT COPIES.

  A pxx open-array parameter is ONE word: a pointer whose length lives at
  [ptr-8], the same convention AnsiString handles and dynamic arrays use. So an
  argument that already carries that header is passed by REFERENCE, and one that
  does not has to be copied into something that does -- the header must be
  adjacent to the data. FPC passes two words, (pointer, high), and therefore
  aliases everything.

  This test pins the rows that are CORRECT today, because they are the ones a
  representation change would silently take away:

    - a DYNAMIC array argument aliases through a `var` and a `const` open-array
      parameter (the caller's element address IS the callee's);
    - a VALUE parameter copies, in pxx AND in FPC, which is what a by-value
      open array MEANS -- this row is not a divergence and an earlier ticket
      claimed it was;
    - element access and WRITE-THROUGH are correct for every argument shape,
      including the ones that copy, because the copy is faithful and copied back.

  IT DOES NOT ASSERT THE STATIC-ARRAY ADDRESS ROWS. Those diverge from FPC
  today -- `@a[0]` inside the callee is the marshalling temp, not the caller's
  array -- and writing today's answer into a .expected would make the suite
  green over a live divergence. It is recorded, with its measurements and the
  reason the fix is a representation change rather than a patch, in
  bug-a-address-of-an-open-array-element-points-at-the-marshalling-temp.

  Runs unmodified under FPC, which is the point: every row here answers the same
  in both compilers, so the file is its own oracle. }

var
  gd: array of LongInt;
  b: PtrUInt;
  aliasVar, aliasVarDyn, aliasConst, valueCopies: Boolean;

procedure TakesVar(var a: array of LongInt);
begin
  aliasVar := PtrUInt(@a[0]) = b;
  a[2] := 99;                      { write-through, whatever the parameter is }
end;

procedure TakesConst(const a: array of LongInt);
begin
  aliasConst := PtrUInt(@a[0]) = b;
end;

procedure TakesValue(a: array of LongInt);
begin
  { A by-value open array is a COPY by definition: its elements have their own
    addresses in both compilers. Asserting `= b` here would be asserting that
    the language is something else. }
  valueCopies := PtrUInt(@a[0]) <> b;
  a[3] := 1234;                    { ...and this must NOT reach the caller }
end;

var
  ls: array[0..3] of LongInt;
  wroteThroughDyn, wroteThroughStatic, valueDidNotEscape: Boolean;
  i: Integer;
begin
  SetLength(gd, 4);
  for i := 0 to 3 do gd[i] := i;
  b := PtrUInt(@gd[0]);
  TakesVar(gd);
  { CAPTURE IT NOW. TakesVar is called again below with a STATIC array, and a
    single shared flag would report that second call's answer under this row's
    name -- which is exactly what the first draft did: FPC printed TRUE where
    pxx printed FALSE and the oracle caught a bug in the TEST, not in the
    compiler. }
  aliasVarDyn := aliasVar;
  TakesConst(gd);
  wroteThroughDyn := gd[2] = 99;

  for i := 0 to 3 do ls[i] := i;
  b := PtrUInt(@ls[0]);
  TakesValue(ls);
  valueDidNotEscape := ls[3] = 3;
  TakesVar(ls);
  wroteThroughStatic := ls[2] = 99;

  WriteLn('dyn aliases var    ', aliasVarDyn);
  WriteLn('dyn aliases const  ', aliasConst);
  WriteLn('value copies       ', valueCopies);
  WriteLn('write thru dyn     ', wroteThroughDyn);
  WriteLn('write thru static  ', wroteThroughStatic);
  WriteLn('value did not esc  ', valueDidNotEscape);
end.
