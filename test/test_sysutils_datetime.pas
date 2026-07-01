program test_sysutils_datetime;
{ feature-sysutils-decodedate-missing: EncodeDate/DecodeDate/EncodeTime/
  DecodeTime added to lib/rtl/sysutils.pas (Howard Hinnant's days_from_civil/
  civil_from_days algorithm, chosen for correctness under this dialect's
  truncating div/mod on negative inputs). Covers round-tripping across leap
  years, century boundaries (1900 non-leap, 2000 leap), the TDateTime epoch
  itself, pre-epoch/pre-1970 dates, combined date+time, and the negative-
  TDateTime edge case (verified against real FPC: the time-of-day fraction is
  the ABSOLUTE VALUE of the leftover fraction, not a floor-adjusted one).
  Output is identical to real FPC's SysUtils. }
uses sysutils;
var
  y, m, d, h, mi, s, ms: Word;
  dt: TDateTime;
begin
  dt := EncodeDate(2026, 7, 2); DecodeDate(dt, y, m, d);
  writeln(y, '-', m, '-', d);                       { 2026-7-2 }

  dt := EncodeDate(2000, 2, 29); DecodeDate(dt, y, m, d);
  writeln(y, '-', m, '-', d);                       { 2000-2-29, leap century }

  dt := EncodeDate(1900, 2, 28); DecodeDate(dt, y, m, d);
  writeln(y, '-', m, '-', d);                       { 1900-2-28, non-leap century }

  dt := EncodeDate(1899, 12, 30); DecodeDate(dt, y, m, d);
  writeln(y, '-', m, '-', d, ' ', dt:0:1);          { 1899-12-30 0.0, the epoch }

  dt := EncodeDate(1899, 12, 29); DecodeDate(dt, y, m, d);
  writeln(y, '-', m, '-', d, ' ', dt:0:1);          { 1899-12-29 -1.0, pre-epoch }

  dt := EncodeDate(1969, 12, 31); DecodeDate(dt, y, m, d);
  writeln(y, '-', m, '-', d);                       { 1969-12-31, pre-Unix-epoch }

  dt := EncodeDate(1800, 1, 1); DecodeDate(dt, y, m, d);
  writeln(y, '-', m, '-', d);                       { 1800-1-1 }

  dt := EncodeDate(2026, 7, 2) + EncodeTime(14, 30, 15, 500);
  DecodeDate(dt, y, m, d); DecodeTime(dt, h, mi, s, ms);
  writeln(y, '-', m, '-', d, ' ', h, ':', mi, ':', s, '.', ms);  { 2026-7-2 14:30:15.500 }

  { Negative TDateTime with a time-of-day fraction: matches real FPC exactly
    (verified) -- decodes as 1899-12-30 18:0:0.0, not 1899-12-29 6:0:0.0. }
  dt := EncodeDate(1899, 12, 29) + EncodeTime(6, 0, 0, 0);
  DecodeDate(dt, y, m, d); DecodeTime(dt, h, mi, s, ms);
  writeln(y, '-', m, '-', d, ' ', h, ':', mi, ':', s, '.', ms);
end.
