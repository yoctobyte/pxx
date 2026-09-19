{ SPDX-License-Identifier: Zlib }
unit mimic_calendar;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `calendar`, the one function That Space Program calls: `timegm`, the
  inverse of `time.gmtime`. `import calendar` resolves here through the NilPy
  import resolver's `mimic_` fallback (see mimic_time's header).

  A PASCAL unit because the arithmetic lives in mimic_time's DaysFromCivil, and
  one calendar shared by gmtime and timegm cannot disagree with itself about a
  leap year.

  CPython's timegm takes any tuple and reads its first six items; this one takes
  a `time.struct_time`, which is what every caller passes it (strptime's and
  gmtime's result). The rest of `calendar` (month tables, isleap, monthrange,
  the text calendars) is absent, and a missing name fails at its call site. }

interface

uses mimic_time;

{ Seconds since the epoch for a UTC struct_time -- gmtime's inverse, so
  timegm(gmtime(t)) = floor(t). Only the date and time-of-day fields are read;
  tm_wday, tm_yday and tm_isdst are ignored, as CPython ignores them. }
function timegm(t: struct_time): Int64;

implementation

function timegm(t: struct_time): Int64;
begin
  Result := DaysFromCivil(t.tm_year, t.tm_mon, t.tm_mday) * 86400
            + Int64(t.tm_hour) * 3600 + Int64(t.tm_min) * 60 + t.tm_sec;
end;

end.
