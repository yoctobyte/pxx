program lib_dateparse;
{ StrToDate / StrToDateTime / TryStrTo* — the parse direction of the date
  surface, added 2026-08-15 (feature-lib-sysutils-strtodate-and-strtodatetime).

  Every row here was measured against FPC 3.2.2 rather than reasoned about, and
  the rows are chosen as the ones an implementation gets WRONG, not one per
  function:

  - ISO input is not universally valid. With the d/m/y default ShortDateFormat,
    StrToDate('2026-08-14') RAISES — it reads 2026 as the day. Hardcoding ISO
    is the obvious wrong implementation, and it passes any test written by the
    same person who wrote it.
  - The separator is DateSeparator, so '/' in the input is a format error even
    though '/' in a FORMAT string means the separator.
  - Field count changes the meaning: one field is a day, two are day+month,
    three follow ShortDateFormat, four raise.
  - A one/two-digit year goes through a SLIDING window (TwoDigitYearCenturyWindow),
    so '49' is 2049 and '99' is 1999 — not a fixed 19xx/20xx cutoff.
  - The two failure classes have different messages ('Invalid date' vs
    '"%s" is not a valid date format') and callers do match on them. }
uses sysutils;

var failures: Integer;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok')
  else begin writeln(tag, '=FAIL'); failures := failures + 1; end;
end;

{ tag=ok when S parses to exactly y-m-d }
procedure Parses(const tag, S: string; y, m, d: Word);
var v: TDateTime; gy, gm, gd: Word;
begin
  try
    v := StrToDate(S);
    DecodeDate(v, gy, gm, gd);
    SayBool(tag, (gy = y) and (gm = m) and (gd = d));
  except
    on e: Exception do SayBool(tag, False);
  end;
end;

{ tag=ok when S raises EConvertError whose message is exactly Msg }
procedure Raises(const tag, S, Msg: string);
var v: TDateTime;
begin
  try
    v := StrToDate(S);
    SayBool(tag, False);
  except
    on e: EConvertError do SayBool(tag, e.Message = Msg);
  end;
end;

var
  v: TDateTime;
  y, m, d: Word;
  h, mi, sec, ms: Word;
  cy, cm, cd: Word;
begin
  failures := 0;
  DecodeDate(Date, cy, cm, cd);

  { --- three fields, ShortDateFormat order (default d/m/y) --- }
  Parses('dmy', '14-08-2026', 2026, 8, 14);
  Parses('trailsep', '14-08-2026-', 2026, 8, 14);   { trailing separator is tolerated }
  Parses('leap', '29-02-2024', 2024, 2, 29);

  { --- ISO is NOT special-cased: 2026 is read as the day --- }
  Raises('iso-raises', '2026-08-14', 'Invalid date');
  Raises('slash', '2026/08/14', '"2026/08/14" is not a valid date format');
  Raises('extra-field', '14-08-2026-99', '"14-08-2026-99" is not a valid date format');
  Raises('with-time', '14-08-2026 12:00', '"14-08-2026 12:00" is not a valid date format');
  Raises('junk', 'x', '"x" is not a valid date format');
  Raises('empty', '', '"" is not a valid date format');
  Raises('day0', '00-08-2026', 'Invalid date');
  Raises('month13', '01-13-2026', 'Invalid date');
  Raises('feb29-common', '29-02-2026', 'Invalid date');

  { --- fewer fields default to TODAY --- }
  Parses('twofield', '08-09', cy, 9, 8);
  Parses('onefield', '15', cy, cm, 15);

  { --- sliding two-digit-year window (pivot moves with the clock) --- }
  Parses('yy26', '01-02-26', 2026, 2, 1);
  Parses('yy49', '01-02-49', 2049, 2, 1);
  Parses('yy50', '01-02-50', 2050, 2, 1);
  Parses('yy99', '01-02-99', 1999, 2, 1);
  Parses('yy00', '01-02-00', 2000, 2, 1);

  { --- ShortDateFormat/DateSeparator really drive it --- }
  DateSeparator := '.';
  ShortDateFormat := 'yyyy.mm.dd';
  Parses('reorder-iso', '2026.08.14', 2026, 8, 14);
  Raises('reorder-dmy', '14.08.2026', 'Invalid date');
  DateSeparator := '-';
  ShortDateFormat := 'd/m/y';

  { --- StrToDateTime: either half alone, or both --- }
  v := StrToDateTime('14-08-2026 12:34:56');
  DecodeDate(v, y, m, d); DecodeTime(v, h, mi, sec, ms);
  SayBool('dt-both', (y = 2026) and (m = 8) and (d = 14) and
                     (h = 12) and (mi = 34) and (sec = 56) and (ms = 0));

  { millisecond FIELD, not a decimal fraction: '.25' is 25 ms, not 250 }
  v := StrToDateTime('14-08-2026 12:34:56.25');
  DecodeTime(v, h, mi, sec, ms);
  SayBool('dt-ms', ms = 25);

  v := StrToDateTime('14-08-2026');
  DecodeDate(v, y, m, d); DecodeTime(v, h, mi, sec, ms);
  SayBool('dt-dateonly', (y = 2026) and (d = 14) and (h = 0) and (mi = 0));

  v := StrToDateTime('12:34:56');
  DecodeTime(v, h, mi, sec, ms);
  SayBool('dt-timeonly', (h = 12) and (mi = 34) and (sec = 56));

  v := StrToDateTime('14-08-2026'#9'12:34:56');
  DecodeTime(v, h, mi, sec, ms);
  SayBool('dt-tab', (h = 12) and (sec = 56));

  { the halves are blamed the right way round: this one is a bad TIME, because
    the token before the space parses fine as a time and the one after does not }
  try
    v := StrToDateTime('12:34:56 14-08-2026');
    SayBool('dt-rev', False);
  except
    on e: EConvertError do
      SayBool('dt-rev', e.Message = '"14-08-2026" is not a valid time');
  end;

  { --- the TryStrTo* arms share the parser: same verdicts, no raising --- }
  v := 1.0;
  SayBool('try-date', TryStrToDate('14-08-2026', v));
  SayBool('try-date-val', Trunc(v) = Trunc(EncodeDate(2026, 8, 14)));
  v := 1.0;
  SayBool('try-date-bad', not TryStrToDate('2026-08-14', v));
  { a failed Try* CLEARS the value, as FPC's out param does — measured }
  SayBool('try-date-cleared', v = 0.0);
  v := 1.0;
  SayBool('try-time', TryStrToTime('12:34:56', v));
  SayBool('try-time-bad', not TryStrToTime('x', v));
  v := 1.0;
  SayBool('try-dt', TryStrToDateTime('14-08-2026 01:02:03', v));
  SayBool('try-dt-bad', not TryStrToDateTime('x', v));

  { --- round trip against the format direction --- }
  v := StrToDate('14-08-2026');
  SayBool('roundtrip', FormatDateTime('dd-mm-yyyy', v) = '14-08-2026');

  if failures = 0 then writeln('lib_dateparse: all ok')
  else writeln('lib_dateparse: ', failures, ' FAIL');
end.
