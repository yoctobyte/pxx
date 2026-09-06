program test_setlength_through_a_string_cast_of_a_pointer_slot;
{ `var p: Pointer; AnsiString(p) := 'abc'; SetLength(AnsiString(p), 2)` is how a
  Delphi-lineage codebase stores strings in untyped slots -- uPSCompiler.pas does
  it 93 times -- and pxx refused it with `SetLength expects a string variable in
  IR codegen`. BOTH spellings failed, the alias and the built-in, which is what
  said the alias was not in the cause.

  THE PARSER DROPS A STRING CAST AROUND A SetLength TARGET, which is right when
  the target is a string variable (row C: `SetLength(t(s), 3)` means
  `SetLength(s, 3)`) and throws away the only evidence there is when the target
  is a POINTER. Rows A and B are that case; C, D and E are the ones that must
  not move.

  ROW F IS THE ONE WORTH HAVING. Growing a managed string reallocates, so the
  NEW handle has to be written back into p's own slot -- if the resize took the
  payload address instead of the slot address it would still print the right
  characters for a shrink and lose the string on a grow. A shrink-only test
  passes either way, and `Length` reading back 5 is what says the write-back
  happened: through a stale handle it would answer 2.

  ROW F DOES NOT WRITE THE NEW CHARACTERS, and that is a boundary rather than
  laziness. `t(r)[3] := 'c'` through a cast over a pointer slot is a SEPARATE
  and still-open defect -- the indexed read answers a blank character where fpc
  answers `b`, the indexed store goes nowhere silently, and the built-in
  spelling does not parse at all
  (bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere).
  Asserting it here would make this file red for a defect it does not fix.
  bug-p-setlength-over-a-string-cast-of-a-pointer-slot-has-no-lowering }
{$mode delphi}
type
  t  = AnsiString;
  TS = string[10];
var
  p, q, r: Pointer;
  s: AnsiString;
  sh: TS;
begin
  t(p) := 'abcd';
  SetLength(t(p), 2);
  WriteLn('A: ', t(p), ' ', Length(t(p)));

  AnsiString(q) := 'wxyz';
  SetLength(AnsiString(q), 3);
  WriteLn('B: ', AnsiString(q), ' ', Length(AnsiString(q)));

  s := 'hello';
  SetLength(t(s), 3);                    { the cast-DROP path, a string variable }
  WriteLn('C: ', s);

  sh := 'frozen';
  SetLength(TS(sh), 3);                  { a FROZEN cast, untouched by this fix }
  WriteLn('D: ', sh);

  s := 'plain';
  SetLength(s, 2);                       { no cast at all }
  WriteLn('E: ', s);

  t(r) := 'ab';
  SetLength(t(r), 5);                    { GROW: the handle must be written back }
  WriteLn('F: [', Copy(t(r), 1, 2), '] ', Length(t(r)));
end.
