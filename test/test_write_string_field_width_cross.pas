{ `Write(s:w)` where s is a string VARIABLE, on every backend.

  i386, aarch64 and arm32 dropped the field width outright: the arms for
  tyString and tyAnsiString emitted write(1, buf, len) and never looked at
  `wid`. x86-64 and riscv32 padded, and so does FPC, so a program printing a
  column-aligned report came out ragged on three of five targets and nothing
  errored. `Write('abcdef':9)` -- the LITERAL -- padded everywhere, which is
  why no existing test saw it: the literal arm reads the width, the variable
  arms did not, one construct with two spellings.

  The three now call PXXWriteFrozenW / PXXWriteStrMW, the portable helpers
  riscv32 and wasm32 already used, rather than growing a fourth and fifth
  inline copy of `max(0, wid - len)` -- the pad is a RUNTIME quantity because
  the length is, and a second copy is the one that stays broken.

  Rows 8-10 are the ones that are new code rather than a new call: a width on
  a CONCAT operand must still release the temporary handle. The loop is sized
  so a leak is an RSS explosion rather than a wrong character.

  Every row diffed against FPC on x86-64, i386, aarch64, arm32 and riscv32.
  bug-a-three-backends-drop-the-field-width-on-a-string-variable }
program test_write_string_field_width_cross;
var s: ShortString; a: AnsiString; e: AnsiString; w, i: Integer;
begin
  s := 'abcdef';
  a := 'abcdef';
  e := '';
  WriteLn('[', s:9, ']');            { ShortString variable, padded }
  WriteLn('[', a:9, ']');            { AnsiString variable, padded }
  WriteLn('[', 'abcdef':9, ']');     { literal -- always worked }
  WriteLn('[', s:2, ']');            { width below the length: no truncation }
  WriteLn('[', a:2, ']');
  WriteLn('[', s:0, '][', a:0, ']'); { no width at all }
  WriteLn('[', e:4, ']');            { empty managed string still pads }
  WriteLn('[', a + 'x':9, ']');      { a CONCAT operand with a width }
  WriteLn('[', (a + 'yz'):10, ']');  { ...parenthesised, the other spelling }
  w := 9;
  WriteLn('[', s:w, '][', a:w, ']'); { the variable-width path }
  { A width WIDER than the 40-byte spaces buffer. Every x86-64 arm emitted one
    unbounded write(fd, spaces, count), so this printed the right NUMBER of
    characters and the wrong ones -- 259 bytes of whatever follows the buffer,
    per line. Length-counting assertions cannot see it; only a byte compare can,
    which is why these two rows are here and not a wc. }
  s := 'y'; a := 'z';
  WriteLn('[', s:60, ']');
  WriteLn('[', a:60, ']');
  { A width on a CONCAT must still release the temporary handle. 20000 rounds,
    9 bytes each: the byte count is the assertion that none was truncated, and
    peak RSS is the assertion that none leaked. Measured 2026-09-02 with the
    fix: 392 KB on x86-64 and i386, and flat on aarch64/arm32 between 20000 and
    200000 rounds -- a per-round leak would scale with the count. }
  for i := 1 to 20000 do
    Write(a + 'q':9);
  WriteLn;
  WriteLn('[', a:9, ']');            { and the value survives the loop }
  WriteLn('WRITE STRING FIELD WIDTH CROSS OK');
end.
