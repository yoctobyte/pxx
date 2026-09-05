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

  DELIBERATELY ABSENT: QWord >= 2^63 and WordBool/LongBool/ByteBool. Those box
  losing information too, but unlike the Single case they are OURS to fix --
  fpc emits vtQWord where we emit vtInt64, and the sized-boolean identity is an
  open Track U fork. So their pairs cannot match today and a row for them would
  be a known-red assertion rather than a test. They are filed, and named in libwriteln.pas's header:
    bug-a-a-qword-boxes-as-vtint64-so-array-of-const-loses-unsignedness
    bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln
  A QWord BELOW 2^63 is included, because that one must and does agree. }
uses libwriteln;
var
  i: Integer;
  i64: Int64;
  q: QWord;
  b: Boolean;
  c: Char;
  sh: ShortString;
  an: AnsiString;
  d: Double;
  sg: Single;
begin
  i := -42; i64 := 9223372036854775807; q := 9000000000;
  b := True; c := 'Z'; sh := 'short'; an := 'ansi'; d := 3.5; sg := 0.5;

  writeln('int      builtin=', i);
  LibWriteLn(['int      library=', i]);

  writeln('int64    builtin=', i64);
  LibWriteLn(['int64    library=', i64]);

  writeln('qword    builtin=', q);
  LibWriteLn(['qword    library=', q]);

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
