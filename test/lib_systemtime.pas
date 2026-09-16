program lib_systemtime;
{ SysUtils.TSystemTime and its two converters.

  FPC's own compiler is the first consumer: globals.pas declares
  `startsystime : TSystemTime` and `getrealtime(const st: TSystemTime)`, reading
  Year/Month/Day and Hour/Minute/Second/MilliSecond. It was wall six of
  umbrella-pxx-compiles-fpc-itself and we simply did not declare the type.

  EVERY EXPECTED VALUE HERE IS DERIVED INDEPENDENTLY, not read off our own
  output. The weekday comes from a calendar (2026-09-16 is a Wednesday), the
  0-vs-1 base from FPC's own source (`Dec(SystemTime.DayOfWeek)` in
  DateTimeToSystemTime, `DayOfWeek(...)-1` in the unix GetLocalTime), and the
  pre-epoch composition from FPC's ComposeDateTime.

  THE THREE ROWS THAT CAN ACTUALLY FAIL, since most of a date struct will look
  right if anything at all was written:

  1. THE VARIANT OVERLAY. The `w`-prefixed arm must be the SAME STORAGE, not a
     second copy -- real source uses both spellings and a two-record version
     would compile everything and hand one of them zeros. Asserted by writing
     through the plain names and reading through the Win32 names, plus
     SizeOf = 16 (eight words, ONE set), which is what separates an overlay
     from a struct that merely has sixteen fields.

  2. DayOfWeek's BASE. The field is 0-based and SysUtils.DayOfWeek is 1-based.
     Both are printed from the same instant so the row asserts the DIFFERENCE,
     which is the only thing that can be wrong here -- a fixture printing just
     one of them passes whichever convention it happens to have been written
     against.

  3. THE PRE-EPOCH COMPOSE, and it is the row with a real discriminator.
     Before 1899-12-30 the day part is negative while the time-of-day fraction
     is positive, so `date + time` runs the clock BACKWARDS through the day:
     1899-12-29 06:00 is -1.25 under FPC's ComposeDateTime and -0.75 under
     naive addition, which decodes as 18:00 on 12-30 -- a plausible wrong
     answer, not a crash. Both numbers are printed so the row cannot pass by
     collapsing onto one. Note dateutils' EncodeDateTime in this tree still
     adds; this is about SystemTimeToDateTime, which takes no hint about its
     own era and therefore must be sign-correct.

  GetLocalTime is UTC here, deliberately -- `Now` reads CLOCK_REALTIME and this
  RTL has no timezone database. It is asserted for AGREEMENT WITH Now rather
  than against any absolute value, which is both the honest claim and the only
  deterministic one. }
uses SysUtils;

var
  s, s2: TSystemTime;
  dt, back, n1: TDateTime;
  ok: Integer;

procedure Chk(const name: string; cond: Boolean);
begin
  if cond then begin WriteLn(name, '=ok'); Inc(ok); end
  else WriteLn(name, '=FAIL');
end;

begin
  ok := 0;

  { ---- a known instant, forward direction ---- }
  dt := EncodeDate(2026, 9, 16) + EncodeTime(13, 45, 7, 250);
  DateTimeToSystemTime(dt, s);
  Chk('year',   s.Year = 2026);
  Chk('month',  s.Month = 9);
  Chk('day',    s.Day = 16);
  Chk('hour',   s.Hour = 13);
  Chk('minute', s.Minute = 45);
  Chk('second', s.Second = 7);
  Chk('msec',   s.MilliSecond = 250);

  { 2026-09-16 is a Wednesday. Field 0-based (0=Sun) -> 3; function 1-based -> 4. }
  Chk('dow-field', s.DayOfWeek = 3);
  Chk('dow-func',  DayOfWeek(dt) = 4);
  Chk('dow-differ-by-one', DayOfWeek(dt) - s.DayOfWeek = 1);

  { ---- the variant arms are ONE storage ---- }
  Chk('w-year',  s.wYear = 2026);
  Chk('w-month', s.wMonth = 9);
  Chk('w-day',   s.wDay = 16);
  Chk('w-hour',  s.wHour = 13);
  Chk('w-min',   s.wMinute = 45);
  Chk('w-sec',   s.wSecond = 7);
  Chk('w-msec',  s.wMilliseconds = 250);
  Chk('w-dow',   s.wDayOfWeek = 3);
  Chk('size-is-one-set', SizeOf(TSystemTime) = 16);

  { ---- round trip ---- }
  back := SystemTimeToDateTime(s);
  Chk('roundtrip', Abs(back - dt) < 1.0E-9);

  { ---- pre-epoch: the sign-correct compose ---- }
  s2.Year := 1899; s2.Month := 12; s2.Day := 29; s2.DayOfWeek := 0;
  s2.Hour := 6; s2.Minute := 0; s2.Second := 0; s2.MilliSecond := 0;
  dt := SystemTimeToDateTime(s2);
  Chk('pre-epoch-compose', Abs(dt - (-1.25)) < 1.0E-9);
  Chk('pre-epoch-not-naive', Abs(dt - (-0.75)) > 0.4);
  DateTimeToSystemTime(dt, s);
  Chk('pre-epoch-back-day',  (s.Year = 1899) and (s.Month = 12) and (s.Day = 29));
  Chk('pre-epoch-back-time', (s.Hour = 6) and (s.Minute = 0));

  { ---- the wall clock, asserted against Now and not against an absolute ---- }
  n1 := Now;
  GetLocalTime(s);
  Chk('getlocaltime-agrees-with-now',
      Abs(SystemTimeToDateTime(s) - n1) < 2.0 / 86400.0);
  Chk('msec-in-range', s.MilliSecond <= 999);
  Chk('getlocaltime-year-sane', s.Year >= 2020);

  WriteLn('lib_systemtime: ', ok, ' checks');
  if ok = 27 then WriteLn('lib_systemtime: all ok')
  else WriteLn('lib_systemtime: FAILURES');
end.
