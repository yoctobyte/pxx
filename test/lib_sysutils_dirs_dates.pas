{ SysUtils directory manipulation, date RENDERING, the tick counter and
  TextToFloat — feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols.

  Every expectation was MEASURED by running this program under fpc 3.2.2 and
  under pxx and diffing. The ones a plausible implementation gets wrong:

  - CreateDir on an EXISTING directory is FALSE. Only ForceDirectories is
    idempotent, so `if not CreateDir(d)` is not the question "does d exist".
  - GetCurrentDir has NO trailing slash, but ExpandFileName('') is the cwd WITH
    one. The two disagree deliberately.
  - ExpandFileName is purely lexical — it collapses '.' and '..' in paths that
    do not exist and never resolves a symlink — but a leading '//' survives
    (POSIX reserves it) while every other run of slashes collapses.
  - DateToStr on the C-locale defaults is '7-3-20', NOT an ISO date: '/' in a
    format string means DateSeparator, which defaults to '-', and a lone 'y' is
    a two-digit year.
  - DateTimeToStr DROPS the time half at exact midnight. A log line that
    normally reads '7-3-20 13:05:09' becomes '7-3-20' once a day.
  - TextToFloat TRIMS surrounding whitespace but REJECTS trailing junk: '1.5x'
    is False, not 1.5.

  The directory cases run under a scratch tree in the temp dir and clean up
  after themselves, so the test is re-runnable and leaves nothing behind. }
program lib_sysutils_dirs_dates;

uses sysutils;

var
  failures: Integer;

procedure Check(ok: Boolean; const what: string);
begin
  if not ok then
  begin
    Writeln('FAIL: ', what);
    failures := failures + 1;
  end;
end;

procedure CheckStr(const got, want, what: string);
begin
  if got <> want then
  begin
    Writeln('FAIL: ', what, ' got [', got, '] want [', want, ']');
    failures := failures + 1;
  end;
end;

var
  root, deep, saved: string;
  d: TDateTime;
  e: Extended;
  t0, t1: Int64;
  i: Integer;

begin
  failures := 0;

  { ---- format settings this RTL and FPC agree on under the C locale ---- }
  CheckStr(ShortDateFormat, 'd/m/y', 'ShortDateFormat default');
  CheckStr(LongTimeFormat, 'hh:nn:ss', 'LongTimeFormat default');
  CheckStr(ShortTimeFormat, 'hh:nn', 'ShortTimeFormat default');
  CheckStr(DateSeparator, '-', 'DateSeparator default');

  { ---- DateToStr / TimeToStr / DateTimeToStr ---- }
  d := EncodeDate(2020, 3, 7) + EncodeTime(13, 5, 9, 0);
  CheckStr(DateToStr(d), '7-3-20', 'DateToStr uses ShortDateFormat, / = DateSeparator');
  CheckStr(TimeToStr(d), '13:05:09', 'TimeToStr uses LongTimeFormat');
  CheckStr(DateTimeToStr(d), '7-3-20 13:05:09', 'DateTimeToStr joins both halves');
  d := EncodeDate(2020, 3, 7);
  CheckStr(DateTimeToStr(d), '7-3-20', 'DateTimeToStr DROPS a zero time');
  CheckStr(DateTimeToStr(d, True), '7-3-20 00:00:00',
           'DateTimeToStr(d, True) forces the zero time back');
  d := EncodeTime(13, 5, 9, 0);
  CheckStr(DateTimeToStr(d), '30-12-99 13:05:09',
           'a pure time carries the 1899-12-30 epoch date');

  { ---- GetTickCount64: monotonic, milliseconds ---- }
  t0 := GetTickCount64;
  Check(t0 > 0, 'GetTickCount64 is positive');
  Sleep(15);
  t1 := GetTickCount64;
  Check(t1 >= t0, 'GetTickCount64 never goes backwards');
  Check(t1 - t0 >= 10, 'GetTickCount64 advances by roughly the slept milliseconds');
  Check(t1 - t0 < 5000, 'GetTickCount64 is milliseconds, not microseconds');

  { ---- TextToFloat ---- }
  e := 0;
  Check(TextToFloat(PChar('1.5'), e), 'TextToFloat accepts a plain decimal');
  Check(e = 1.5, 'TextToFloat value');
  e := 0;
  Check(TextToFloat(PChar('  2.5  '), e), 'TextToFloat trims surrounding blanks');
  Check(e = 2.5, 'TextToFloat trimmed value');
  e := 0;
  Check(TextToFloat(PChar('-1e3'), e), 'TextToFloat accepts an exponent');
  Check(e = -1000.0, 'TextToFloat exponent value');
  Check(not TextToFloat(PChar('abc'), e), 'TextToFloat rejects a non-number');
  Check(not TextToFloat(PChar(''), e), 'TextToFloat rejects the empty buffer');
  Check(not TextToFloat(PChar('1.5x'), e), 'TextToFloat rejects TRAILING junk');

  { ---- FloatToStrF, FPC's FOUR-argument form ----
    Which of Precision/Digits is read depends on the format, and it is not the
    "before/after the point" split the names suggest: ffFixed/ffNumber/
    ffCurrency ignore Precision and take the decimal count from DIGITS, while
    ffExponent reads Precision as significant digits and Digits as the minimum
    width of the EXPONENT field. All measured against FPC. }
  CheckStr(FloatToStrF(1234.5678, ffFixed, 15, 2), '1234.57', 'ffFixed 2 decimals');
  CheckStr(FloatToStrF(1234.5678, ffFixed, 15, 0), '1235', 'ffFixed 0 decimals rounds');
  CheckStr(FloatToStrF(1234.5678, ffFixed, 2, 2), '1234.57',
           'ffFixed IGNORES Precision — this is not 2 significant digits');
  CheckStr(FloatToStrF(0.5, ffFixed, 15, 3), '0.500', 'ffFixed pads to Digits');
  CheckStr(FloatToStrF(0.0, ffFixed, 15, 2), '0.00', 'ffFixed of zero');
  CheckStr(FloatToStrF(1234.5678, ffGeneral, 15, 0), '1234.5678',
           'ffGeneral keeps the value at 15 significant digits');
  CheckStr(FloatToStrF(1234.5678, ffGeneral, 4, 0), '1235',
           'ffGeneral READS Precision as significant digits');
  CheckStr(FloatToStrF(1e20, ffGeneral, 15, 0), '1E20',
           'ffGeneral switches to the exponent form when the point runs away');
  CheckStr(FloatToStrF(0.0, ffGeneral, 15, 0), '0', 'ffGeneral of zero');
  CheckStr(FloatToStrF(1234.5678, ffExponent, 5, 2), '1.2346E+03',
           'ffExponent: 5 significant digits, exponent padded to 2');
  CheckStr(FloatToStrF(1234.5678, ffExponent, 15, 0), '1.23456780000000E+3',
           'ffExponent with Digits 0 does NOT pad the exponent');
  CheckStr(FloatToStrF(-0.5, ffExponent, 3, 1), '-5.00E-1', 'ffExponent, negative');
  CheckStr(FloatToStrF(1234567.891, ffNumber, 15, 2), '1,234,567.89',
           'ffNumber groups thousands');
  CheckStr(FloatToStrF(-1234.5, ffNumber, 15, 1), '-1,234.5', 'ffNumber, negative');
  CheckStr(FloatToStrF(1234.5, ffCurrency, 15, 2), '1,234.50$',
           'ffCurrency: CurrencyFormat 1 puts the symbol last');
  CheckStr(FloatToStrF(-1234.5, ffCurrency, 15, 2), '-1,234.50$',
           'ffCurrency: NegCurrFormat 5');
{$IFDEF PXX}
  { The two-argument form is a pxx invention (examples/mandelbrot and
    examples/raytracer call it) and FPC has no such overload, so this one
    assertion is guarded — the REST of the file must stay compilable by FPC,
    which is how every expectation above was measured. }
  CheckStr(FloatToStrF(3.14159, 2), '3.14',
           'the two-argument pxx form still resolves alongside the FPC one');
{$ENDIF}

  { ---- ExpandFileName: lexical, cwd-anchored ---- }
  saved := GetCurrentDir;
  Check(SetCurrentDir(GetTempDir), 'SetCurrentDir into the temp dir');
  CheckStr(ExpandFileName('/a/b'), '/a/b', 'an absolute path passes through');
  CheckStr(ExpandFileName('/a/./b/../c'), '/a/c', 'dot and dot-dot collapse lexically');
  CheckStr(ExpandFileName('/a/b/'), '/a/b/', 'a trailing slash is PRESERVED');
  CheckStr(ExpandFileName('//a//b'), '//a/b',
           'a LEADING double slash survives; other runs collapse');
  CheckStr(ExpandFileName('/..'), '/', 'dot-dot at the root stays at the root');
  CheckStr(ExpandFileName('/a/..'), '/', 'dot-dot back to the root');
  CheckStr(ExpandFileName('/'), '/', 'the root itself');
  Check(ExpandFileName('') = IncludeTrailingPathDelimiter(GetCurrentDir),
        'the EMPTY name expands to the cwd WITH a trailing slash');
  Check(ExpandFileName('.') = GetCurrentDir,
        'a lone dot expands to the cwd WITHOUT one');

  { ---- CreateDir / RemoveDir / ForceDirectories round trip ---- }
  root := IncludeTrailingPathDelimiter(GetTempDir) + 'pxx-dirs-test';
  deep := root + '/a/b';
  { clean any leftovers from an interrupted earlier run }
  RemoveDir(deep);
  RemoveDir(root + '/a');
  RemoveDir(root);

  Check(not DirectoryExists(root), 'the scratch tree does not exist yet');
  Check(ForceDirectories(deep), 'ForceDirectories creates the missing parents');
  Check(DirectoryExists(deep), 'the deep directory is there');
  Check(DirectoryExists(root), 'and so is its parent');
  Check(ForceDirectories(deep), 'ForceDirectories on an EXISTING tree is True');
  Check(not CreateDir(deep), 'CreateDir on an existing directory is FALSE');
  Check(not RemoveDir(root), 'RemoveDir refuses a NON-EMPTY directory');
  Check(RemoveDir(deep), 'RemoveDir removes an empty leaf');
  Check(RemoveDir(root + '/a'), 'and then its parent');
  Check(RemoveDir(root), 'and then the root');
  Check(not DirectoryExists(root), 'the scratch tree is gone');
  Check(not RemoveDir(root), 'RemoveDir of a missing directory is False');

  { ---- SetCurrentDir / GetCurrentDir ---- }
  Check(not SetCurrentDir(root), 'SetCurrentDir into a missing directory is False');
  Check(GetCurrentDir <> '', 'GetCurrentDir returns something');
  i := Length(GetCurrentDir);
  Check((i = 1) or (GetCurrentDir[i] <> '/'),
        'GetCurrentDir has NO trailing slash (unlike ExpandFileName of "")');
  Check(SetCurrentDir(saved), 'SetCurrentDir back where we started');

  { ---- RenameFile ---- }
  Check(not RenameFile(IncludeTrailingPathDelimiter(GetTempDir) + 'pxx-no-such-file',
                       IncludeTrailingPathDelimiter(GetTempDir) + 'pxx-no-such-file2'),
        'RenameFile of a missing source is False, not an exception');

  { ---- FileGetDate ---- }
  Check(FileGetDate(9999) = -1, 'FileGetDate of a bad handle is -1');

  if failures = 0 then Writeln('SYSUTILSDIRSDATES OK')
  else Writeln('SYSUTILSDIRSDATES ', failures, ' FAILURES');
end.
