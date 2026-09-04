program test_shortstring_in_array_of_const;
{ A ShortString passed to `array of const` must arrive as usable text.

  It did not. `tyString` covers TWO shapes with different layouts, and the
  boxing arm handled only one: a frozen string LITERAL is an interned blob
  behind an 8-byte length prefix, while a ShortString VARIABLE is
  `[len: Byte][chars]`. The arm added 8 unconditionally, so a variable's text
  was skipped past -- EMPTY for a 5-char ShortString, GARBAGE for a `string[5]`
  where offset 8 is outside the buffer.

  WHY THE ROWS ARE THESE ROWS:

  * `stale` is the row an offset-only fix would still get wrong. A ShortString
    has no guaranteed NUL: after 'longer' then 'ab' the buffer still reads
    'ab' + 'ger', so a consumer holding only a char pointer over-reads. The
    length has to be applied, not stepped over. Expect `ab`, and `abger` is the
    specific wrong answer this row exists to catch.
  * `s5` is a `string[5]`, whose whole buffer is shorter than the 8 bytes the
    old arm skipped -- it read past the variable entirely and printed whatever
    was next in the frame. Its right answer is a full-capacity string, so a
    truncation bug cannot hide in it either.
  * `lit` and `konst` are the CONTROL, and they are load-bearing rather than
    padding: both were always correct via the +8 fast path, and the compiler's
    own asm-text emitters build vectors of exactly this shape, so a fix that
    repaired variables by making every literal allocate would be a self-host
    performance regression these rows pin against.
  * `empty` separates "renders nothing because it is empty" from "renders
    nothing because the pointer is unusable" -- the pre-fix failure mode.

  Byte-identical to fpc 3.2.2 -Mdelphi -O1.
  bug-a-a-shortstring-in-array-of-const-boxes-an-unusable-pointer }
uses sysutils;
const
  KONST = 'konstant';
var
  sh: ShortString;
  s5: string[5];
  an: AnsiString;
begin
  sh := 'short';
  writeln('plain=', Format('%s', [sh]));

  sh := 'longer'; sh := 'ab';
  writeln('stale=', Format('%s', [sh]));

  s5 := 'five5';
  writeln('s5=', Format('%s', [s5]));

  sh := '';
  writeln('empty=[', Format('%s', [sh]), ']');

  writeln('lit=', Format('%s', ['literal']));
  writeln('konst=', Format('%s', [KONST]));

  { mixed vector: the element AFTER a ShortString must still line up }
  sh := 'mid';
  an := 'tail';
  writeln('mixed=', Format('%s|%d|%s', [sh, 7, an]));

  { the same value through the renderer that was always right }
  sh := 'short';
  writeln('builtin=', sh);

  writeln('SHORTSTRING VARREC OK');
end.
