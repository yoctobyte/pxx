{ `Write(s:w)` on a SHORTSTRING when w is not wider than the string.

  The x86-64 arm padded with `max(0, w - len)` spaces and jumped over the pad
  with a HAND-COUNTED `jle +35`. The span it counts is
  `mov rsi,imm64` + `mov rdx,rax` + MovRaxImm + MovRdiImm + EmitSyscall, and
  three of those five are emitters that pick an encoding. They now emit 27
  bytes, so the jump landed EIGHT BYTES PAST its target, inside the following
  EmitwriteStrVar, and the write went out with the wrong length:

      s := 'abcdef';  WriteLn(s:2, '|')   printed  `|`        (FPC: abcdef|)
      s := 'abcdef';  WriteLn(s:6, '|')   printed  `a|`       (FPC: abcdef|)

  Nothing caught it because `var s: string` is an ANSISTRING here, and the
  AnsiString arm forty lines below already patched its jump instead of counting
  it -- so test_write_char_field_width's `s:1` row, written for exactly this
  question, exercised the arm that was already right. The two spellings of one
  construct, and the fix went into one of them (normalise-dont-special-case.md).

  The pad path (w > len) was always correct: the jump is not taken there, which
  is why every column-alignment test in the tree passed.

  Rows diffed against FPC. bug-a-hand-written-literal-short-jumps-span-emitters-that-can-grow }
program test_write_shortstring_field_width_narrower;
var s: ShortString; e: ShortString; w: Integer;
begin
  s := 'abcdef';
  e := '';
  WriteLn('[', s:2, ']');      { width BELOW the length -- jle taken }
  WriteLn('[', s:6, ']');      { width EQUAL to the length -- sub = 0, jle taken }
  WriteLn('[', s:9, ']');      { width above -- the pad path, jle not taken }
  WriteLn('[', s:0, ']');      { zero width }
  WriteLn('[', e:0, ']');      { empty string, zero width }
  WriteLn('[', e:3, ']');      { empty string, padded }
  Write('[', s:1, ']['); Write(s:3); WriteLn(']');   { two narrow writes in one line }
  w := 2;
  WriteLn('[', s:w, ']');      { the variable-width path, same question }
  WriteLn('WRITE SHORTSTRING NARROW FIELD WIDTH OK');
end.
