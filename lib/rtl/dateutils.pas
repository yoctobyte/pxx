{ SPDX-License-Identifier: Zlib }
unit dateutils;
{ Minimal FPC-compatible DateUtils shim (feature-synapse-compile-check —
  ftpsend pulls it). Grown on demand; TDateTime plumbing lives in sysutils. }

interface

uses sysutils;

function YearOf(const AValue: TDateTime): Word;
function MonthOf(const AValue: TDateTime): Word;
function DayOf(const AValue: TDateTime): Word;
function HourOf(const AValue: TDateTime): Word;
function MinuteOf(const AValue: TDateTime): Word;
function SecondOf(const AValue: TDateTime): Word;
function EncodeDateTime(Year, Month, Day, Hour, Minute, Second, MilliSecond: Word): TDateTime;

implementation

function EncodeDateTime(Year, Month, Day, Hour, Minute, Second, MilliSecond: Word): TDateTime;
begin
  Result := EncodeDate(Year, Month, Day) + EncodeTime(Hour, Minute, Second, MilliSecond);
end;

function YearOf(const AValue: TDateTime): Word;
var y, m, d: Word;
begin
  DecodeDate(AValue, y, m, d);
  Result := y;
end;

function MonthOf(const AValue: TDateTime): Word;
var y, m, d: Word;
begin
  DecodeDate(AValue, y, m, d);
  Result := m;
end;

function DayOf(const AValue: TDateTime): Word;
var y, m, d: Word;
begin
  DecodeDate(AValue, y, m, d);
  Result := d;
end;

function HourOf(const AValue: TDateTime): Word;
var h, mi, s, ms: Word;
begin
  DecodeTime(AValue, h, mi, s, ms);
  Result := h;
end;

function MinuteOf(const AValue: TDateTime): Word;
var h, mi, s, ms: Word;
begin
  DecodeTime(AValue, h, mi, s, ms);
  Result := mi;
end;

function SecondOf(const AValue: TDateTime): Word;
var h, mi, s, ms: Word;
begin
  DecodeTime(AValue, h, mi, s, ms);
  Result := s;
end;

end.
