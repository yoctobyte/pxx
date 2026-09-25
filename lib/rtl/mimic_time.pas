{ SPDX-License-Identifier: Zlib }
unit mimic_time;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `time` — the three clock entry points real code reaches for.

  `import time` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See
  devdocs/dev/python-compat-tiers.md.

  A PASCAL unit, for the same reason as [[mimic_shutil]]: these are syscalls.
  The PAL already has them at FULL RESOLUTION — PalClockGetTime hands back
  separate seconds and NANOseconds, and PalNanosleep takes the same pair — so
  this shim is a unit conversion and nothing more. There is no approximation
  here to apologise for.

  WHY NOT GetTickCount64, which was the obvious candidate: it is
  PalMonotonicMillis, so it is correctly monotonic and it is MILLISECONDS.
  lekkerzeilen calls `time.monotonic()` eighteen times and they are frame
  timing; at 60 fps a frame is 16.7 ms, so a 1 ms quantum is 6% of a frame and
  it lands in a dt that drives physics. CPython's `monotonic()` is
  nanosecond-sourced, and so is this. Resolution is part of this function's
  contract, not a quality-of-implementation detail.

  THE SUBSET: `monotonic`, `time`, `sleep`, `perf_counter`, and since
  2026-09-19 the calendar half That Space Program reaches for: `struct_time`,
  `gmtime(secs)`, `strptime(s, fmt)` and `strftime(fmt[, t])`, whose format
  directives are %Y %m %d %H %M %S %j and %%. Any other directive raises
  ValueError naming it rather than printing something plausible. `perf_counter`
  is `monotonic`: both read the nanosecond-sourced CLOCK_MONOTONIC here, and a
  real program (tsp/ephem/bench.py) calls it, which outweighs the reason it
  was once left out.

  LOCAL TIME IS UTC, BY THIS RTL'S STANDING RULE AND NOT BY THIS FILE'S CHOICE.
  sysutils has no timezone database and its GetLocalTime returns UTC (see its
  comment there), so `strftime(fmt)` with no tuple formats the current UTC
  time, where CPython uses localtime(). On a UTC machine the two agree. The day
  a zone database lands in sysutils, this follows it.

  `struct_time` is a class with the nine `tm_*` fields, not CPython's tuple
  subclass, so it cannot be indexed or unpacked. Nothing that calls it does
  either; `calendar.timegm` (mimic_calendar) reads the fields.

  Absent, and said out loud rather than approximated: `localtime`/`mktime`
  (they need that zone database), `monotonic_ns`/`time_ns` (trivial once
  someone needs them; the nanoseconds are right here), and `process_time`.
  A missing name fails at the call site naming the member, which is found in
  one run.

  THE CLOCK IDS ARE LINUX NUMBERS AND THAT IS A REAL LIMIT. 0 is CLOCK_REALTIME
  (platform.pas's own comment for PalClockGetTime says so: "PalRealtime is one
  fixed case of (clockId 0)") and 1 is CLOCK_MONOTONIC. Those two happen to
  agree across Linux, the BSDs and Minix. They are NOT universal — a backend
  that numbers its clocks differently needs the ids moved behind the PAL, which
  is where they belong and where PalClockGetTime's own comment already points.
  Whoever ports this: the fix is a PAL constant, not a table here. }

interface

uses platform, pylib, sysutils;

type
  { `time.struct_time`, fields only -- see the unit header. tm_wday counts from
    Monday = 0 and tm_yday from 1, as CPython's do. }
  struct_time = class
  public
    tm_year, tm_mon, tm_mday, tm_hour, tm_min, tm_sec: Integer;
    tm_wday, tm_yday, tm_isdst: Integer;
  end;

{ Seconds from an arbitrary origin, never going backwards. CPython leaves the
  origin undefined for exactly this reason, so CLOCK_MONOTONIC's boot-relative
  origin is conforming and callers may only subtract two readings. }
function monotonic: Double;

{ Seconds since the Unix epoch, as a float. Can jump, in both directions --
  it is the wall clock. }
function time: Double;

{ Suspend for `seconds`, which may be fractional. }
procedure sleep(seconds: Double);

{ CLOCK_MONOTONIC, as `monotonic` -- see the unit header. }
function perf_counter: Double;

{ Seconds since the epoch to a UTC struct_time. A fractional or negative time
  rounds toward minus infinity, as CPython's does, so -0.5 is 23:59:59 the
  day before. }
function gmtime(secs: Double): struct_time;

{ Seconds since the epoch to LOCAL time: the zone TZ names, else
  /etc/localtime (a TZif file, footer rule included), with tm_isdst set. No
  zone to read -- a board, a container without one -- is UTC, which is also
  MicroPython's own localtime. The no-argument form is the current time. }
function localtime(secs: Double): struct_time; overload;
function localtime: struct_time; overload;

{ Parse `s` against `fmt`. Fields the format does not name default to
  CPython's 1900-01-01 00:00:00, and tm_isdst is -1. A mismatch, an
  out-of-range field or unconverted trailing text raises ValueError. }
function strptime(const s, fmt: AnsiString): struct_time;

{ Format `t`, or the current LOCAL time when it is omitted, as CPython does. }
function strftime(const fmt: AnsiString; t: struct_time = nil): AnsiString;

{ MicroPython's extensions to `time` (and all of `utime`, which is this module
  under its old name -- lib/rtl/mimic_utime.py). A MicroPython program and its
  device drivers write `time.sleep_ms(10)` and `time.ticks_diff(...)`; NilPy is
  upward compatible with CPython, so carrying the extra names costs a CPython
  program nothing. The ticks are MicroPython's: they wrap at 2**30
  (TICKS_PERIOD), so ticks_diff and ticks_add are the ONLY correct arithmetic
  on them, exactly as its docs require. }
procedure sleep_ms(ms: Int64);
procedure sleep_us(us: Int64);
function ticks_ms: Int64;
function ticks_us: Int64;
function ticks_cpu: Int64;
function ticks_diff(ticks1, ticks2: Int64): Int64;
function ticks_add(ticks, delta: Int64): Int64;

{ Pascal surface: days from 1970-01-01 to a proleptic Gregorian date, and
  back. Shared with mimic_calendar's timegm, so there is one calendar here. }
function DaysFromCivil(y, m, d: Int64): Int64;
procedure CivilFromDays(z: Int64; out y, m, d: Int64);

implementation

const
  { See the unit header on why these live here and why that is a limit. }
  PY_CLOCK_REALTIME  = 0;
  PY_CLOCK_MONOTONIC = 1;
  NSEC_PER_SEC       = 1000000000;

{ Seconds and nanoseconds to one Double.

  The nanoseconds are divided BEFORE the addition, not after, so the sum is
  formed at the scale of the result. CLOCK_REALTIME's seconds are ~1.7e9 today,
  which needs 31 bits, and a Double's 53-bit mantissa leaves 22 bits for the
  fraction -- about 240 ns. That is the real floor on `time()` and it is
  CPython's floor too, for the same reason: a float carrying an absolute epoch
  has spent most of its precision on the integer part. `monotonic()` does not
  have this problem, its seconds being a small boot-relative number. }
function SecNsecToSeconds(sec, nsec: Int64): Double;
begin
  Result := Double(sec) + Double(nsec) / Double(NSEC_PER_SEC);
end;

function ReadClock(clockId: Integer): Double;
var sec, nsec: Int64;
begin
  sec := 0;
  nsec := 0;
  { A failing clock read returns 0.0 rather than raising. CPython would raise
    OSError, and matching that would be better -- but a clock this program
    cannot read is not a condition any caller here handles, and a frame loop
    that suddenly raises out of its timing call is a worse failure than one
    whose dt comes out zero. Revisit when something actually wants the error. }
  if PalClockGetTime(clockId, sec, nsec) <> 0 then
    Result := 0.0
  else
    Result := SecNsecToSeconds(sec, nsec);
end;

function monotonic: Double;
begin
  Result := ReadClock(PY_CLOCK_MONOTONIC);
end;

function time: Double;
begin
  Result := ReadClock(PY_CLOCK_REALTIME);
end;

procedure sleep(seconds: Double);
var sec, nsec: Int64;
    whole: Double;
begin
  { A DELIBERATE, MEASURED DIVERGENCE, and in the permitted direction.
    `sleep(0)` returns at once in CPython too. `sleep(-1)` does NOT: CPython
    raises `ValueError: sleep length must be non-negative` (verified, 3.14).
    This accepts it and returns.

    NilPy is UPWARD compatible with CPython -- accepting what CPython rejects is
    a feature, one direction (CLAUDE.md; nilpy-semantics-divergences.md). The
    reason to take that latitude here rather than matching: the idiom this
    protects is `sleep(deadline - now())`, which goes negative exactly when the
    loop is already behind, and raising there converts a missed frame into a
    crash. Feeding a negative tv_nsec to nanosleep(2) is EINVAL besides.

    So code written for CPython behaves identically, and code written against
    this will not port back unchanged. That asymmetry is the point of the rule,
    not an oversight -- and it is why the differential fixture does NOT include
    a negative row: it would be a row the oracle cannot run. }
  { A BLOCKING POINT IS A PUMP POINT. Deferred work registered through
    platform.PalPendingDrain is delivered here, AFTER the wait rather than
    before it, because the events worth delivering are the ones that arrived
    DURING the window we just spent not looking. Draining first would run the
    callbacks on the queue as it was before the sleep and leave everything the
    sleep covered sitting until the next one.

    `sleep(0)` drains too and is the deliberate yield spelling: it returns at
    once, so a program that wants to service pending work without waiting has a
    spelling that costs nothing. It is also why the drain is on BOTH exits from
    this routine and not only the tail.

    Nil unless something installed it -- see platform.PalDrainPending. A program
    that registers no handler pays one pointer test.
    feature-s-interrupt-events-reach-python-outside-interrupt-context }
  if seconds <= 0.0 then
  begin
    PalDrainPending;
    Exit;
  end;
  whole := Int(seconds);
  sec := Trunc(whole);
  nsec := Trunc((seconds - whole) * Double(NSEC_PER_SEC));
  { Rounding can land exactly on a full second; nanosleep(2) requires
    tv_nsec < 1e9. }
  if nsec >= NSEC_PER_SEC then
  begin
    nsec := nsec - NSEC_PER_SEC;
    sec := sec + 1;
  end;
  if nsec < 0 then
    nsec := 0;
  PalNanosleep(sec, nsec);
  PalDrainPending;
end;

const
  TICKS_PERIOD = Int64(1) shl 30;

procedure sleep_ms(ms: Int64);
begin
  if ms > 0 then sleep(ms / 1000.0);
end;

procedure sleep_us(us: Int64);
begin
  if us > 0 then sleep(us / 1000000.0);
end;

function ticks_ms: Int64;
begin
  Result := Trunc(monotonic * 1000.0) and (TICKS_PERIOD - 1);
end;

function ticks_us: Int64;
begin
  Result := Trunc(monotonic * 1000000.0) and (TICKS_PERIOD - 1);
end;

function ticks_cpu: Int64;
begin
  Result := ticks_us;
end;

{ MicroPython's definition: the signed distance in (-PERIOD/2, PERIOD/2]. }
function ticks_diff(ticks1, ticks2: Int64): Int64;
begin
  Result := ((ticks1 - ticks2 + (TICKS_PERIOD div 2)) and (TICKS_PERIOD - 1))
            - (TICKS_PERIOD div 2);
end;

function ticks_add(ticks, delta: Int64): Int64;
begin
  Result := (ticks + delta) and (TICKS_PERIOD - 1);
end;

function perf_counter: Double;
begin
  Result := ReadClock(PY_CLOCK_MONOTONIC);
end;

{ Howard Hinnant's days_from_civil / civil_from_days: exact over the whole
  proleptic Gregorian calendar with no table, and one algorithm in both
  directions, so a round trip cannot drift. }
function FloorDiv(a, b: Int64): Int64;
begin
  Result := a div b;
  if ((a mod b) <> 0) and ((a < 0) <> (b < 0)) then Result := Result - 1;
end;

function DaysFromCivil(y, m, d: Int64): Int64;
var era, yoe, doy, doe, mp: Int64;
begin
  if m <= 2 then y := y - 1;
  era := FloorDiv(y, 400);
  yoe := y - era * 400;
  if m > 2 then mp := m - 3 else mp := m + 9;
  doy := (153 * mp + 2) div 5 + d - 1;
  doe := yoe * 365 + yoe div 4 - yoe div 100 + doy;
  Result := era * 146097 + doe - 719468;
end;

procedure CivilFromDays(z: Int64; out y, m, d: Int64);
var era, doe, yoe, doy, mp: Int64;
begin
  z := z + 719468;
  era := FloorDiv(z, 146097);
  doe := z - era * 146097;
  yoe := (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365;
  y := yoe + era * 400;
  doy := doe - (365 * yoe + yoe div 4 - yoe div 100);
  mp := (5 * doy + 2) div 153;
  d := doy - (153 * mp + 2) div 5 + 1;
  if mp < 10 then m := mp + 3 else m := mp - 9;
  if m <= 2 then y := y + 1;
end;

function IsLeap(y: Int64): Boolean;
begin
  Result := ((y mod 4) = 0) and (((y mod 100) <> 0) or ((y mod 400) = 0));
end;

function DaysInMonth(y, m: Int64): Int64;
begin
  case m of
    2: if IsLeap(y) then Result := 29 else Result := 28;
    4, 6, 9, 11: Result := 30;
  else
    Result := 31;
  end;
end;

{ The two derived fields, from the date. 1970-01-01 was a Thursday, which is 3
  counting from Monday = 0. }
procedure FillDerived(st: struct_time);
var days: Int64;
begin
  days := DaysFromCivil(st.tm_year, st.tm_mon, st.tm_mday);
  st.tm_wday := Integer(days + 3 - FloorDiv(days + 3, 7) * 7);
  st.tm_yday := Integer(days - DaysFromCivil(st.tm_year, 1, 1) + 1);
end;

function gmtime(secs: Double): struct_time;
var whole, days, rem, y, m, d: Int64;
begin
  whole := Trunc(secs);
  if Double(whole) > secs then whole := whole - 1;
  days := FloorDiv(whole, 86400);
  rem := whole - days * 86400;
  CivilFromDays(days, y, m, d);
  Result := struct_time.Create;
  Result.tm_year := Integer(y);
  Result.tm_mon := Integer(m);
  Result.tm_mday := Integer(d);
  Result.tm_hour := Integer(rem div 3600);
  Result.tm_min := Integer((rem mod 3600) div 60);
  Result.tm_sec := Integer(rem mod 60);
  Result.tm_isdst := 0;
  FillDerived(Result);
end;

{ ---- local time ------------------------------------------------------------
  The zone is loaded ONCE, on the first localtime: TZ if set (a zone name under
  /usr/share/zoneinfo, an absolute path, or a POSIX rule such as
  `CET-1CEST,M3.5.0,M10.5.0/3`), else /etc/localtime. A TZif file supplies its
  transitions (the 64-bit v2 block when there is one) and, past the last of
  them, its footer rule -- which is ALL a "slim" zone file carries. }
var
  TzLoaded: Boolean;             { globals start zeroed }
  TzTrans: array of Int64;       { transition instants, UTC seconds }
  TzTransType: array of Integer; { the ttinfo each one switches to }
  TzOff: array of Int64;         { ttinfo: seconds EAST of UTC }
  TzDst: array of Integer;       { ttinfo: is_dst }
  TzRule: AnsiString;            { POSIX footer, '' when absent }

function TzBE(const b: AnsiString; at, n: Integer): Int64;
var i: Integer;
begin
  Result := 0;
  for i := 0 to n - 1 do Result := (Result shl 8) or Ord(b[at + i]);
  { sign-extend a 4-byte field }
  if (n = 4) and (Result >= $80000000) then Result := Result - $100000000;
end;

function TzReadFile(const path: AnsiString; out data: AnsiString): Boolean;
var fd: Integer; got: Int64; buf: array[0..4095] of Char; i: Integer;
begin
  data := '';
  Result := False;
  fd := PalOpen(PChar(path), 0, 0);
  if fd < 0 then Exit;
  repeat
    got := PalRead(fd, @buf[0], 4096);
    for i := 0 to Integer(got) - 1 do data := data + buf[i];
  until (got <= 0) or (Length(data) > 1048576);
  PalClose(fd);
  Result := (Length(data) >= 44) and (Copy(data, 1, 4) = 'TZif');
end;

procedure TzParseFile(const b: AnsiString);
var p, isut, isstd, leap, tcnt, ycnt, ccnt, tsz, i, e: Integer;
begin
  p := 1;                                          { 1-based header start }
  tsz := 4;
  if (b[5] >= '2') then
  begin
    { skip the v1 block to the v2 header, whose times are 8 bytes }
    isut := TzBE(b, p + 20, 4); isstd := TzBE(b, p + 24, 4);
    leap := TzBE(b, p + 28, 4); tcnt := TzBE(b, p + 32, 4);
    ycnt := TzBE(b, p + 36, 4); ccnt := TzBE(b, p + 40, 4);
    p := p + 44 + tcnt * 4 + tcnt + ycnt * 6 + ccnt + leap * 8 + isstd + isut;
    if (p + 44 > Length(b) + 1) or (Copy(b, p, 4) <> 'TZif') then Exit;
    tsz := 8;
  end;
  isut := TzBE(b, p + 20, 4); isstd := TzBE(b, p + 24, 4);
  leap := TzBE(b, p + 28, 4); tcnt := TzBE(b, p + 32, 4);
  ycnt := TzBE(b, p + 36, 4); ccnt := TzBE(b, p + 40, 4);
  p := p + 44;
  if p + tcnt * (tsz + 1) + ycnt * 6 > Length(b) + 1 then Exit;
  SetLength(TzTrans, tcnt); SetLength(TzTransType, tcnt);
  for i := 0 to tcnt - 1 do TzTrans[i] := TzBE(b, p + i * tsz, tsz);
  p := p + tcnt * tsz;
  for i := 0 to tcnt - 1 do TzTransType[i] := Ord(b[p + i]);
  p := p + tcnt;
  SetLength(TzOff, ycnt); SetLength(TzDst, ycnt);
  for i := 0 to ycnt - 1 do
  begin
    TzOff[i] := TzBE(b, p + i * 6, 4);
    TzDst[i] := Ord(b[p + i * 6 + 4]);
  end;
  p := p + ycnt * 6 + ccnt + leap * (tsz + 4) + isstd + isut;
  { the footer: "\n<rule>\n", v2+ only }
  if (tsz = 8) and (p <= Length(b)) and (b[p] = #10) then
  begin
    e := p + 1;
    while (e <= Length(b)) and (b[e] <> #10) do Inc(e);
    TzRule := Copy(b, p + 1, e - p - 1);
  end;
end;

procedure TzLoad;
var tz, data: AnsiString; i: Integer;
begin
  TzLoaded := True;
  TzRule := '';
  tz := GetEnvironmentVariable('TZ');
  { SET but EMPTY is UTC (glibc, and so CPython) -- not the same as unset }
  if tz = '' then
    for i := 1 to GetEnvironmentVariableCount do
      if GetEnvironmentString(i) = 'TZ=' then Exit;
  if (tz <> '') and (tz[1] = ':') then tz := Copy(tz, 2, Length(tz));
  if tz = '' then
  begin
    if TzReadFile('/etc/localtime', data) then TzParseFile(data);
    Exit;
  end;
  if (tz[1] = '/') and TzReadFile(tz, data) then begin TzParseFile(data); Exit; end;
  if TzReadFile('/usr/share/zoneinfo/' + tz, data) then begin TzParseFile(data); Exit; end;
  TzRule := tz;                                    { a bare POSIX rule }
end;

{ POSIX rule pieces. A name is letters, or <...> with anything inside. }
procedure TzSkipName(const r: AnsiString; var i: Integer);
begin
  if (i <= Length(r)) and (r[i] = '<') then
  begin
    while (i <= Length(r)) and (r[i] <> '>') do Inc(i);
    Inc(i);
  end
  else
    while (i <= Length(r)) and (((r[i] >= 'A') and (r[i] <= 'Z')) or
                                ((r[i] >= 'a') and (r[i] <= 'z'))) do Inc(i);
end;

function TzNum(const r: AnsiString; var i: Integer): Int64;
begin
  Result := 0;
  while (i <= Length(r)) and (r[i] >= '0') and (r[i] <= '9') do
  begin
    Result := Result * 10 + Ord(r[i]) - Ord('0');
    Inc(i);
  end;
end;

{ [+-]hh[:mm[:ss]] as seconds, sign as written }
function TzHms(const r: AnsiString; var i: Integer): Int64;
var neg: Boolean;
begin
  neg := False;
  if (i <= Length(r)) and ((r[i] = '+') or (r[i] = '-')) then
  begin
    neg := r[i] = '-';
    Inc(i);
  end;
  Result := TzNum(r, i) * 3600;
  if (i <= Length(r)) and (r[i] = ':') then
  begin
    Inc(i); Result := Result + TzNum(r, i) * 60;
    if (i <= Length(r)) and (r[i] = ':') then begin Inc(i); Result := Result + TzNum(r, i); end;
  end;
  if neg then Result := -Result;
end;

{ `Mm.w.d[/time]` -> the UTC instant in year y, given the offset in effect
  just before it. False for the Jn / n forms, which this does not read. }
function TzRuleInstant(const r: AnsiString; var i: Integer; y, offBefore: Int64;
                       out inst: Int64): Boolean;
var m, w, d, first, dow1, mday, secs: Int64;
begin
  Result := False;
  inst := 0;
  if (i > Length(r)) or (r[i] <> 'M') then Exit;
  Inc(i); m := TzNum(r, i);
  if (i > Length(r)) or (r[i] <> '.') then Exit;
  Inc(i); w := TzNum(r, i);
  if (i > Length(r)) or (r[i] <> '.') then Exit;
  Inc(i); d := TzNum(r, i);
  secs := 7200;                                    { 02:00 by default }
  if (i <= Length(r)) and (r[i] = '/') then begin Inc(i); secs := TzHms(r, i); end;
  if (m < 1) or (m > 12) then Exit;
  first := DaysFromCivil(y, m, 1);
  { weekday of the 1st, Sunday = 0; 1970-01-01 was a Thursday }
  dow1 := first + 4 - FloorDiv(first + 4, 7) * 7;
  mday := 1 + (d - dow1 + 7) mod 7 + (w - 1) * 7;
  while mday > DaysInMonth(y, m) do mday := mday - 7;
  inst := (DaysFromCivil(y, m, mday)) * 86400 + secs - offBefore;
  Result := True;
end;

{ The offset (seconds east) and dst flag a POSIX rule gives instant t. }
function TzRuleOffset(const r: AnsiString; t: Int64; out isdst: Integer): Int64;
var i: Integer; stdOff, dstOff, y, mo, d, s1, s2: Int64; hasDst: Boolean;
begin
  isdst := 0;
  i := 1;
  TzSkipName(r, i);
  stdOff := -TzHms(r, i);                          { POSIX offsets are WEST }
  Result := stdOff;
  if i > Length(r) then Exit;
  TzSkipName(r, i);
  dstOff := stdOff + 3600;
  if (i <= Length(r)) and (r[i] <> ',') then dstOff := -TzHms(r, i);
  hasDst := (i <= Length(r)) and (r[i] = ',');
  if not hasDst then Exit;
  Inc(i);
  CivilFromDays(FloorDiv(t + stdOff, 86400), y, mo, d);
  if not TzRuleInstant(r, i, y, stdOff, s1) then Exit;
  if (i > Length(r)) or (r[i] <> ',') then Exit;
  Inc(i);
  if not TzRuleInstant(r, i, y, dstOff, s2) then Exit;
  if s1 < s2 then hasDst := (t >= s1) and (t < s2)     { northern }
  else hasDst := not ((t >= s2) and (t < s1));         { southern }
  if hasDst then begin Result := dstOff; isdst := 1; end;
end;

function TzOffsetAt(t: Int64; out isdst: Integer): Int64;
var lo, hi, mid, k: Integer;
begin
  if not TzLoaded then TzLoad;
  isdst := 0;
  Result := 0;
  if Length(TzOff) = 0 then
  begin
    if TzRule <> '' then Result := TzRuleOffset(TzRule, t, isdst);
    Exit;
  end;
  if (Length(TzTrans) = 0) or (t < TzTrans[0]) then
  begin
    { before the first transition: the first standard-time type }
    k := 0;
    while (k < Length(TzDst)) and (TzDst[k] <> 0) do Inc(k);
    if k >= Length(TzDst) then k := 0;
    if (Length(TzTrans) = 0) and (TzRule <> '') then
    begin
      Result := TzRuleOffset(TzRule, t, isdst);
      Exit;
    end;
    Result := TzOff[k]; isdst := TzDst[k];
    Exit;
  end;
  if (t >= TzTrans[High(TzTrans)]) and (TzRule <> '') then
  begin
    Result := TzRuleOffset(TzRule, t, isdst);
    Exit;
  end;
  lo := 0; hi := High(TzTrans);
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if TzTrans[mid] <= t then lo := mid else hi := mid - 1;
  end;
  k := TzTransType[lo];
  if (k >= 0) and (k < Length(TzOff)) then
  begin
    Result := TzOff[k]; isdst := TzDst[k];
  end;
end;

function localtime(secs: Double): struct_time;
var whole, off: Int64; dst: Integer;
begin
  whole := Trunc(secs);
  if Double(whole) > secs then whole := whole - 1;
  off := TzOffsetAt(whole, dst);
  Result := gmtime(Double(whole + off));
  Result.tm_isdst := dst;
end;

function localtime: struct_time;
begin
  Result := localtime(time);
end;

function StrptimeMismatch(const s, fmt: AnsiString): ValueError;
begin
  Result := ValueError.Create('time data ''' + s + ''' does not match format ''' + fmt + '''');
end;

function IsSpace(c: Char): Boolean;
begin
  Result := (c = ' ') or (c = #9) or (c = #10) or (c = #13);
end;

function strptime(const s, fmt: AnsiString): struct_time;
var i, j, n, maxw, v: Integer;
    c: Char;
begin
  Result := struct_time.Create;
  Result.tm_year := 1900;
  Result.tm_mon := 1;
  Result.tm_mday := 1;
  Result.tm_isdst := -1;
  i := 1;
  j := 1;
  while j <= Length(fmt) do
  begin
    c := fmt[j];
    if (c = '%') and (j < Length(fmt)) then
    begin
      c := fmt[j + 1];
      j := j + 2;
      if c = '%' then
      begin
        if (i > Length(s)) or (s[i] <> '%') then raise StrptimeMismatch(s, fmt);
        i := i + 1;
        Continue;
      end;
      case c of
        'Y': maxw := 4;
        'm', 'd', 'H', 'M', 'S': maxw := 2;
      else
        raise ValueError.Create('strptime: directive %' + c + ' is not supported by this shim');
      end;
      n := 0;
      v := 0;
      while (n < maxw) and (i <= Length(s)) and (s[i] >= '0') and (s[i] <= '9') do
      begin
        v := v * 10 + (Ord(s[i]) - Ord('0'));
        i := i + 1;
        n := n + 1;
      end;
      if (n = 0) or ((c = 'Y') and (n <> 4)) then raise StrptimeMismatch(s, fmt);
      case c of
        'Y': Result.tm_year := v;
        'm': if (v < 1) or (v > 12) then raise StrptimeMismatch(s, fmt) else Result.tm_mon := v;
        'd': if (v < 1) or (v > 31) then raise StrptimeMismatch(s, fmt) else Result.tm_mday := v;
        'H': if v > 23 then raise StrptimeMismatch(s, fmt) else Result.tm_hour := v;
        'M': if v > 59 then raise StrptimeMismatch(s, fmt) else Result.tm_min := v;
        'S': if v > 61 then raise StrptimeMismatch(s, fmt) else Result.tm_sec := v;
      end;
    end
    else if IsSpace(c) then
    begin
      { CPython turns format whitespace into \s+: one or more of any. }
      if (i > Length(s)) or not IsSpace(s[i]) then raise StrptimeMismatch(s, fmt);
      while (i <= Length(s)) and IsSpace(s[i]) do i := i + 1;
      j := j + 1;
    end
    else
    begin
      if (i > Length(s)) or (s[i] <> c) then raise StrptimeMismatch(s, fmt);
      i := i + 1;
      j := j + 1;
    end;
  end;
  if i <= Length(s) then
    raise ValueError.Create('unconverted data remains: ' + Copy(s, i, Length(s) - i + 1));
  if Result.tm_mday > DaysInMonth(Result.tm_year, Result.tm_mon) then
    raise ValueError.Create('day ' + IntToStr(Result.tm_mday) + ' must be in range 1..'
      + IntToStr(DaysInMonth(Result.tm_year, Result.tm_mon)) + ' for month '
      + IntToStr(Result.tm_mon) + ' in year ' + IntToStr(Result.tm_year));
  FillDerived(Result);
end;

function Pad(v, width: Integer): AnsiString;
begin
  Result := IntToStr(v);
  while Length(Result) < width do Result := '0' + Result;
end;

function strftime(const fmt: AnsiString; t: struct_time = nil): AnsiString;
var j: Integer;
    c: Char;
begin
  if t = nil then t := localtime(time);
  Result := '';
  j := 1;
  while j <= Length(fmt) do
  begin
    c := fmt[j];
    if (c = '%') and (j < Length(fmt)) then
    begin
      c := fmt[j + 1];
      j := j + 2;
      case c of
        'Y': Result := Result + IntToStr(t.tm_year);
        'm': Result := Result + Pad(t.tm_mon, 2);
        'd': Result := Result + Pad(t.tm_mday, 2);
        'H': Result := Result + Pad(t.tm_hour, 2);
        'M': Result := Result + Pad(t.tm_min, 2);
        'S': Result := Result + Pad(t.tm_sec, 2);
        'j': Result := Result + Pad(t.tm_yday, 3);
        '%': Result := Result + '%';
      else
        raise ValueError.Create('strftime: directive %' + c + ' is not supported by this shim');
      end;
    end
    else
    begin
      Result := Result + c;
      j := j + 1;
    end;
  end;
end;

end.
