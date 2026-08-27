{ Unsigned 64-bit RENDERING, the direction sysutils did not have.

  The unit parsed unsigned (StrToQWord/StrToQWordDef/TryStrToQWord) and printed
  signed: one IntToStr(Int64), and a Format arm reading `'d', 'u':` that ran
  both specifiers through it. So every QWord at or above 2^63 came back
  negative from IntToStr, and '%u' was a plain synonym for '%d' --
  IntToStr(High(QWord)) answered -1 while WriteLn of the same variable printed
  18446744073709551615, one value rendered two ways in one program.

  Three tickets, one missing mechanism:
    [[bug-b-inttostr-of-a-qword-prints-it-signed]]
    [[bug-b-inttostr-of-a-qword-above-2-63-renders-negative]]
    [[bug-b-format-percent-u-prints-a-signed-value]]

  The fix adds ONE unsigned digit loop (UIntToStr) and routes IntToStr(QWord)
  and '%u' through it, rather than giving each caller its own signedness
  decision -- devdocs/dev/normalise-dont-special-case.md.

  Every line below is fpc 3.2.2's output, byte for byte, including the rows
  that were already right (WriteLn, Str, IntToHex, '%x') -- those are the
  controls that say the value was never wrong, only its rendering. Note two
  rows that surprise: '%d' of a QWord is SIGNED in fpc too, and IntToStr of a
  Cardinal keeps picking the Int64 arm. }
program lib_qword_render;
uses SysUtils;
var q: QWord; i: Integer; c: Cardinal; w: Word; b: Byte; i64: Int64; s: AnsiString;
begin
  { 1 -- the boundary value, and the WriteLn control beside it }
  q := QWord($8000000000000000);
  WriteLn(q);
  WriteLn(IntToStr(q));
  WriteLn(UIntToStr(q));
  Str(q, s); WriteLn(s);

  { 2 -- High(QWord), where the signed reading answered -1 }
  q := QWord($FFFFFFFFFFFFFFFF);
  WriteLn(q);
  WriteLn(IntToStr(q));
  WriteLn(UIntToStr(q));

  { 3 -- through the operators that produce a top-bit-set QWord. The ticket
    surfaced disguised as a shift bug; none of these ever computed wrong. }
  q := QWord($8000000000000000);
  WriteLn(IntToStr(q or 1));
  WriteLn(IntToStr(q + 0));
  WriteLn(IntToStr(q * 1));
  WriteLn(IntToStr(q div 1));
  WriteLn(IntToStr(q shl 0));
  WriteLn(IntToStr(not QWord(0)));

  { 4 -- '%u' is not '%d'. A 32-bit argument prints 32-bit unsigned, which is
    only recoverable from the variant tag because Format widens on the way in. }
  q := QWord($FFFFFFFFFFFFFFFF); i := -1; i64 := -1;
  WriteLn(Format('%u', [q]));
  WriteLn(Format('%d', [q]));
  WriteLn(Format('%u', [i]));
  WriteLn(Format('%d', [i]));
  WriteLn(Format('%u', [i64]));
  WriteLn(Format('%.5u', [i]));
  WriteLn('[' + Format('%22u', [q]) + ']');
  WriteLn('[' + Format('%-22u', [q]) + ']');

  { 5 -- the narrower unsigned types, which widen losslessly into Int64 and
    were never affected. IntToStr(c) must still reach the SIGNED arm. }
  c := 4294967295; w := 65535; b := 255;
  WriteLn(IntToStr(c), ' ', IntToStr(w), ' ', IntToStr(b));
  WriteLn(UIntToStr(c));
  WriteLn(Format('%u %u %u', [c, w, b]));

  { 6 -- zero and one, the loop's own edges }
  WriteLn(UIntToStr(QWord(0)), ' ', UIntToStr(QWord(1)), ' ', IntToStr(QWord(0)));

  { 7 -- controls: hex and the parse direction were already unsigned, and the
    round trip closes only if both halves agree }
  WriteLn(IntToHex(q, 16));
  WriteLn(Format('%x', [q]));
  WriteLn(IntToStr(StrToQWord(IntToStr(q))));
  WriteLn(IntToStr(StrToQWord('18446744073709551615')));
end.
