program test_builtin_pointer_cast_as_target;
{ A builtin pointer-name cast is an assignment TARGET, not only an expression.
  `PInteger(p)^ := 42;` was "undefined variable (PInteger)" as a statement while
  `WriteLn(PInteger(p)^)` on the next line compiled -- and the handful of names
  that did work as targets (PByte, PWord, PInt32, PInt64, PDouble) were exactly
  the ones declared for real in the always-linked prelude, i.e. found by
  FindTypeAlias like any source alias. One concept, two lookup paths; only the
  expression path had the fallback to the builtin name table.

  PChar is here too and is deliberately NOT in that table: it lowers through the
  -2 adapter, which skips a string operand's inline length prefix, so
  `PChar(s)^ := 'H'` edits the string's first CHARACTER. A plain `^Char` alias
  would have written into the handle.

  Every row is fpc 3.2.2's own output on this source (the string is built with
  Copy so it is heap-allocated: fpc SEGFAULTS writing through a PChar into a
  literal-backed string, which is a property of the literal, not of the cast).
  bug-p-a-builtin-pointer-cast-is-refused-as-an-assignment-target }
type
  TR = record a: Integer; b: Char; end;
  PR = ^TR;
var
  p: Pointer;
  s: AnsiString;
  r: TR;
begin
  s := Copy('hello', 1, 5);
  PChar(s)^ := 'H';
  WriteLn('string  : ', s);
  p := GetMem(64);
  PInteger(p)^ := 42;
  WriteLn('pint    : ', PInteger(p)^);
  PCardinal(p)^ := 7;
  WriteLn('pcard   : ', PCardinal(p)^);
  PLongInt(p)^ := -11;
  WriteLn('plongint: ', PLongInt(p)^);
  PBoolean(p)^ := True;
  WriteLn('pbool   : ', PBoolean(p)^);
  PNativeInt(p)^ := -9;
  WriteLn('pnative : ', PNativeInt(p)^);
  PSmallInt(p)^ := -3;
  WriteLn('psmall  : ', PSmallInt(p)^);
  PQWord(p)^ := 123456789;
  WriteLn('pqword  : ', PQWord(p)^);
  PSingle(p)^ := 1.5;
  WriteLn('psingle : ', PSingle(p)^:0:2);
  { ...and a USER alias and a record field chain through the same statement path }
  p := @r;
  PR(p)^.a := 5;
  PR(p)^.b := 'z';
  WriteLn('rec     : ', r.a, r.b);
  PChar(p)^ := 'Q';
  WriteLn('pchar p : ', PChar(p)^);
end.
