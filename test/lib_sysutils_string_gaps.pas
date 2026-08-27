{ The four gaps a 22-program string differential against fpc 3.2.2 found on
  2026-08-21 (bug-b-sysutils-string-gaps-found-by-differential). Two of them
  were fixed elsewhere before this test existed, and BOTH rows are kept: a gap
  that closed without a test is a gap that can reopen without one.

  1. Concat variadic / with Chars — fixed in the COMPILER, not here. `uses
     sysutils` used to withdraw the variadic intrinsic because a two-argument
     Concat was in scope, so `Concat('a','b','c')` became "no overload of
     Concat matches these arguments" (compat-pascal-uses-sysutils-withdraws-
     the-variadic-concat). The intrinsic folds it to `+`; adding an
     `array of const` overload HERE would divert those calls back into a
     TVarRec-building library call, which is why there isn't one.
  2. AnsiQuotedStr — was genuinely missing; QuotedStr is now written as its
     ' case rather than carrying a second copy of the doubling loop.
  3. SameStr — already present, with AnsiSameStr beside it.
  4. TryStr* left the value untouched on failure where fpc zeroes it. The
     date/time three already cleared; the four scalar ones did not.

  Every line below was diffed against fpc 3.2.2 and is byte-identical to it. }
program lib_sysutils_string_gaps;
uses sysutils;
var i: LongInt; i64: Int64; q: QWord; d: Double; ok: Boolean;
begin
  { 1 — the variadic intrinsic survives `uses sysutils` }
  WriteLn(Concat('a', 'b', 'c'));
  WriteLn(Concat('x', 'y'));
  WriteLn(Concat('one ', 'two ', 'three ', 'four'));
  { 2 — quote with any character, doubling it inside }
  WriteLn(AnsiQuotedStr('it''s', '"'));
  WriteLn(AnsiQuotedStr('a"b', '"'));
  WriteLn(QuotedStr('it''s'));
  { 3 — the case-sensitive twin of SameText }
  WriteLn(SameStr('abc', 'abc'), ' ', SameStr('abc', 'ABC'));
  WriteLn(SameText('abc', 'ABC'));
  { 4 — a failed conversion ZEROES the value; the caller's stale one is gone }
  i := -1;   ok := TryStrToInt('q', i);        WriteLn(ok, ' ', i);
  i64 := -1; ok := TryStrToInt64('q', i64);    WriteLn(ok, ' ', i64);
  q := 7;    ok := TryStrToQWord('q', q);      WriteLn(ok, ' ', q);
  d := -1.5; ok := TryStrToFloat('q', d);      WriteLn(ok, ' ', d:0:1);
  { ...and a SUCCESSFUL one still delivers, which is the control }
  i := -1;   ok := TryStrToInt('42', i);       WriteLn(ok, ' ', i);
end.
