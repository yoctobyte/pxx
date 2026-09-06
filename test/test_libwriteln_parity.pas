program test_libwriteln_parity;
{ Phase 3 of feature-writeln-as-library: the library write/writeln must render
  every type BYTE-IDENTICALLY to the builtin it coexists with.

  THE ROWS ARE PAIRS ON PURPOSE. Each type is printed twice -- once through the
  builtin, once through `libwriteln` -- so a divergence names the type in the
  diff instead of reporting "output differs". The two lines of a pair being
  identical is the assertion; the expect_same row pins the bytes so both cannot
  drift together, and the fpc 3.2.2 -Mdelphi oracle says those bytes are the
  RIGHT ones rather than merely agreed.

  THE FLOAT ROW IS THE ONE THAT DISCRIMINATES. A library renderer reaching for
  the obvious tool -- sysutils.FloatToStr -- prints `3.5`, while the builtin
  prints ` 3.5000000000000000E+000`. Every other row would still pass with that
  mistake in place. It is why VarRecToText goes through Str and not FloatToStr,
  and this row is what pins that.

  ONE PAIR IS ASSERTED AS DIFFERENT: `single`. See the note at that row -- the
  loss is in the tag space and fpc shares it exactly, so there is nothing to
  fix and the row exists to notice if that ever changes.

  DELIBERATELY ABSENT: WordBool/LongBool/ByteBool, which box as vtInteger and
  render as 1/0 where the builtin prints TRUE/FALSE. The sized-boolean identity
  is an open Track U fork, so a row for them would be a known-red assertion
  rather than a test:
    bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln

  QWord >= 2^63 USED TO BE ABSENT HERE FOR THE SAME REASON AND NO LONGER IS.
  The old text said "fpc emits vtQWord where we emit vtInt64"; d210325a6 gave
  QWord its own tag and that sentence stopped being true. The row is now
  asserted, and it is the row that matters most in this file: fixing the boxing
  silently broke the RENDERING, because libwriteln's `case` over tags returned
  the empty string for a tag nobody had added an arm for. The below-2^63 row is
  what went red and caught it; this row would not have, since it was absent.
  A negative assertion expires when the feature it denies lands, and the way to
  notice is to re-read the reason, not the row.

  THE TWO QWord ROWS FAIL DIFFERENTLY AND BOTH ARE NEEDED. Measured on this
  file by breaking the fix two ways rather than one:

    no arm for vtQWord at all      -> BOTH rows render '' (the `else` arm)
    arm present, read through a
    ^Int64 instead of a ^QWord     -> the small row still renders 9000000000
                                      and ONLY `qwordbig` diverges, to
                                      -446744073709551616

  So the below-2^63 row cannot see a wrong POINTER TYPE -- signed and unsigned
  readings of those eight bytes are equal, which is the whole reason the tag
  divergence was quiet for as long as it was -- and the above-2^63 row is the
  only thing in this file that can. Deleting either row leaves a defect class
  with nothing watching it. }
uses libwriteln;
var
  i: Integer;
  i64: Int64;
  q: QWord;
  qb: QWord;   { >= 2^63: unsigned or it comes back negative }
  b: Boolean;
  c: Char;
  sh: ShortString;
  an: AnsiString;
  d: Double;
  sg: Single;
begin
  i := -42; i64 := 9223372036854775807; q := 9000000000;
  qb := 18000000000000000000;
  b := True; c := 'Z'; sh := 'short'; an := 'ansi'; d := 3.5; sg := 0.5;

  writeln('int      builtin=', i);
  LibWriteLn(['int      library=', i]);

  writeln('int64    builtin=', i64);
  LibWriteLn(['int64    library=', i64]);

  writeln('qword    builtin=', q);
  LibWriteLn(['qword    library=', q]);

  writeln('qwordbig builtin=', qb);
  LibWriteLn(['qwordbig library=', qb]);

  writeln('bool     builtin=', b);
  LibWriteLn(['bool     library=', b]);

  writeln('boolF    builtin=', False);
  LibWriteLn(['boolF    library=', False]);

  writeln('char     builtin=', c);
  LibWriteLn(['char     library=', c]);

  writeln('short    builtin=', sh);
  LibWriteLn(['short    library=', sh]);

  writeln('ansi     builtin=', an);
  LibWriteLn(['ansi     library=', an]);

  { the discriminating row -- FloatToStr would give `3.5` here }
  writeln('double   builtin=', d);
  LibWriteLn(['double   library=', d]);

  { THE ONE PAIR THAT MUST NOT MATCH, and it is asserted as different rather
    than omitted. A Single boxes as vtExtended -- there is no vtSingle, in this
    compiler OR in fpc -- so the width is gone by the time any vector reader
    sees it, and the library renders the Double form. The builtin sees the
    static type and uses the Single form.
    NOT A PXX DEFECT: measured, fpc prints ` 5.000000000E-01` for
    writeln(Single) and ` 5.0000000000000000E-001` for writeln(Double), exactly
    as we do, and an fpc library writeln over array of const would lose the
    same width for the same reason. It is a property of the tag space.
    Asserted deliberately: if a vtSingle ever appears, this row goes RED and
    tells whoever added it that the library can now do better. An omitted row
    would have said nothing. }
  writeln('single   builtin=', sg);
  LibWriteLn(['single   library=', sg]);

  writeln('literal  builtin=', 'lit');
  LibWriteLn(['literal  library=', 'lit']);

  { mixed vector, and the bracket-elided spelling phase 1 made possible --
    without it this whole unit is unusable, so it is part of the contract }
  writeln('mixed    builtin=', i, '|', b, '|', an);
  LibWriteLn('mixed    library=', i, '|', b, '|', an);

  { write without a newline, then finish the line }
  write('partial  builtin=');
  writeln('yes');
  LibWrite(['partial  library=']);
  LibWriteLn(['yes']);

  writeln('LIBWRITELN PARITY OK');
end.
