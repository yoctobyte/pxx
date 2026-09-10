{ FPC's System-unit array SEARCH family, plus the two Compare widths that were
  missing beside CompareByte: IndexByte / IndexWord / IndexDWord / IndexQWord
  and CompareWord / CompareDWord.

  They are here for the same reason `Prefetch` is: FPC's own compiler calls
  them. `TFPList.IndexOf` (cclasses.pas:885) picks IndexDWord or IndexQWord by
  pointer width under a `{$if}`, so BOTH arms must resolve for either to
  compile. Once the unit cycle, `bitsizeof` and `PSizeUInt` were out of the
  way, `undefined variable (IndexQWord)` became the first failure of most of
  the remaining units (umbrella-pxx-compiles-fpc-itself).

  THIS FILE NAMES NO ROUTINE THAT WAS ALREADY WIRED, AND THAT IS THE POINT.
  `CompareByte` and `CompareChar` were already in the builtin auto-include scan
  in pasparser_prog.inc; these six were not, so they were DECLARED in
  builtin.pas and still answered `undefined variable`, because nothing dragged
  the unit in. The first draft of this test called CompareByte alongside them
  and passed -- one wired name pulls the unit and every unwired name in the
  same program resolves for free. A whole-family test is exactly the shape that
  cannot see this. Revert the pasparser_prog.inc hunk and this file must fail
  to COMPILE; that is its positive control, and CompareByte's own rows live in
  test_p_comparebyte_returns_the_signed_difference.pas so they cannot restore
  it by accident.

  On the values: `len` counts ELEMENTS, not bytes. R07 is the row that says so
  -- with len read as bytes it answers -1 rather than 1 (measured, both
  compilers). R04 and R09 are NOT discriminating for that question: a
  byte-reading implementation answers -1 there too, same as the correct one.
  They pin that a short len stops the scan, which is a different claim.
  umbrella-pxx-compiles-fpc-itself }
program test_p_index_and_compare_family;

var
  fails: LongInt;
  b: array[0..5] of Byte;
  w: array[0..3] of Word;
  d: array[0..3] of DWord;
  q: array[0..3] of QWord;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got = want then
    WriteLn(what, ' ok')
  else
  begin
    WriteLn(what, ' FAIL got=', got, ' want=', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  b[0]:=10; b[1]:=20; b[2]:=30; b[3]:=20; b[4]:=40; b[5]:=50;
  w[0]:=100; w[1]:=200; w[2]:=300; w[3]:=200;
  d[0]:=1000; d[1]:=2000; d[2]:=3000; d[3]:=2000;
  q[0]:=100000; q[1]:=200000; q[2]:=300000; q[3]:=200000;

  { FIRST match, not any match -- b[1] and b[3] both hold 20 }
  Chk('R01 IndexByte first',  IndexByte(b, 6, 20), 1);
  Chk('R02 IndexByte miss',   IndexByte(b, 6, 99), -1);
  Chk('R03 IndexByte len0',   IndexByte(b, 0, 10), -1);
  Chk('R04 IndexByte short',  IndexByte(b, 1, 20), -1);
  Chk('R05 IndexWord',        IndexWord(w, 4, 200), 1);
  Chk('R06 IndexDWord',       IndexDWord(d, 4, 2000), 1);
  { len IS elements: read as bytes, 4 covers no whole QWord and this is -1 }
  Chk('R07 IndexQWord',       IndexQWord(q, 4, 200000), 1);
  Chk('R08 IndexQWord miss',  IndexQWord(q, 4, 7), -1);
  Chk('R09 IndexQWord short', IndexQWord(q, 1, 200000), -1);

  Chk('R10 CompareWord eq',   CompareWord(w, w, 4), 0);
  Chk('R11 CompareDWord eq',  CompareDWord(d, d, 4), 0);

  WriteLn('fails=', fails);
  WriteLn('IDXFAM OK');
end.
