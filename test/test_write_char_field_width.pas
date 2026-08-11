{ `write(c:width)` on a CHAR.

  x86-64 -- the DEFAULT target -- was the only backend that dropped the field
  width: its tyChar arm called EmitwriteChar with no padding, while aarch64,
  arm32, i386 and riscv32 all pad (riscv32 even has a PXXWriteCharW builtin for
  it). FPC pads. So the one target everybody builds with was the odd one out,
  and every column-aligned report written with `write(ch:n)` came out ragged,
  silently.

  A ONE-CHARACTER LITERAL IS A CHAR in Pascal, so `write('a':3)` took the same
  path -- which is why `write('ab':3)` (a string) looked fine and `'a':3` did
  not, the usual two-spellings split.

  Every row diffed against FPC, and against all five backends.
  bug-a-x86-64-write-ignores-a-field-width-on-a-char }

{ ...and the VARIABLE-width half, added with
  bug-a-a-variable-field-width-is-refused-for-strings-and-needs-an-rtl-unit:
  `v:w` was refused outright for strings, Chars and Booleans (the literal path
  formats all three inline, so the two paths disagreed about what is writable),
  and even for an Integer it needed a `uses` clause — a bare program got
  "write(Text): StrInt not loaded", naming a Text file it never opened and a
  routine the user never wrote. This program has NO uses clause on purpose. }
program test_write_char_field_width;
var c: Char; i: Integer; w: Integer; s: string; b: Boolean; d: Double;
begin
  c := 'q';
  WriteLn('[', 'ab':5, ']');      { string literal -- was already right }
  WriteLn('[', 'a':5, ']');       { one-char literal IS a Char }
  WriteLn('[', c:5, ']');         { a Char variable }
  WriteLn('[', #65:5, ']');       { a control character literal }
  WriteLn('[', Chr(66):5, ']');   { a Char-valued expression }
  WriteLn('[', c:1, '][', c:0, ']');  { width <= 1 must not pad }
  i := 5;
  WriteLn('[', i:5, '][', True:8, ']');  { the neighbours that always worked }
  Write('x':4, 'y':4); WriteLn;   { two padded chars in one Write }
  { the same rows with a VARIABLE width — every one of these was refused }
  w := 5; s := 'ab'; b := True; d := 3.5;
  WriteLn('[', s:w, ']');
  WriteLn('[', c:w, ']');
  WriteLn('[', b:w, ']');
  WriteLn('[', i:w, ']');
  WriteLn('[', d:w:2, ']');
  WriteLn('[', s:1, '][', 'abc':w, ']');   { narrower than the value: no truncation }
  WriteLn('WRITE CHAR FIELD WIDTH OK');
end.
