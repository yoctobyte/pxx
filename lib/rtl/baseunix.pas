{ SPDX-License-Identifier: Zlib }
unit baseunix;
{ Minimal FPC-compatible BaseUnix shim (feature-synapse-compile-check).

  Only the surface the Synapse FPC/UNIX branch actually touches: the `timeval`
  type family and `fpgettimeofday`. Wall-clock comes from a CLOCK_REALTIME
  clock_gettime syscall (self-contained, like lib/rtl/ansiterm.pas — the raw
  syscall number is selected per arch here rather than going through the PAL
  public API, which has no clock surface yet).

  NOT a port of FPC's BaseUnix — grow it only as further units demand symbols. }

interface

type
  cint    = LongInt;
  ptimeval  = ^timeval;
  ptimezone = ^timezone;

  timeval = record
    tv_sec:  Int64;   { seconds since the Unix epoch }
    tv_usec: Int64;   { microseconds }
  end;
  TTimeVal = timeval;
  PTimeVal = ptimeval;

  timezone = record
    tz_minuteswest: cint;
    tz_dsttime:     cint;
  end;
  TTimeZone = timezone;
  PTimeZone = ptimezone;

{ Fills tp with the current wall-clock time. tzp is accepted for signature
  compatibility and ignored (CLOCK_REALTIME carries no zone). Returns 0 on
  success, -1 on failure. }
function fpgettimeofday(tp: ptimeval; tzp: ptimezone): cint;
function fpsettimeofday(tp: ptimeval; tzp: ptimezone): cint;

implementation

{ CLOCK_REALTIME = 0. Native-width timespec matches the kernel's per-arch
  layout (see TTimeSpec in the posix PAL backend). }
type
  TKernelTimeSpec = record
    Sec:  NativeInt;
    Nsec: NativeInt;
  end;

function SysClockGettime: Integer;
begin
  Result := -1;
  {$ifdef CPUX86_64} Result := 228; {$endif}
  {$ifdef CPU_I386}  Result := 265; {$endif}
  {$ifdef CPU_AARCH64} Result := 113; {$endif}
  {$ifdef CPU_ARM32} Result := 263; {$endif}
end;

{ settimeofday(2). Fails with -1 (EPERM) for unprivileged callers — exactly
  what Synapse's SetUTTime expects on an ordinary box. }
function fpsettimeofday(tp: ptimeval; tzp: ptimezone): cint;
var
  ts: TKernelTimeSpec;
  n: Int64;
begin
  Result := -1;
  if tp = nil then Exit;
  { clock_settime(CLOCK_REALTIME) is the modern syscall shape; build the
    timespec from the caller's timeval. }
  ts.Sec := tp^.tv_sec;
  ts.Nsec := tp^.tv_usec * 1000;
{$ifdef CPUX86_64}
  n := __pxxrawsyscall(227, 0, Int64(@ts), 0, 0, 0, 0);   { clock_settime }
{$else}
  n := -1;   { other targets: report failure until a consumer needs it }
{$endif}
  if n = 0 then Result := 0;
end;

function fpgettimeofday(tp: ptimeval; tzp: ptimezone): cint;
var
  ts: TKernelTimeSpec;
  n: Integer;
  res: Int64;
begin
  Result := -1;
  if tp = nil then Exit;
  n := SysClockGettime;
  if n = -1 then Exit;
  res := __pxxrawsyscall(n, 0, Int64(@ts), 0, 0, 0, 0); { CLOCK_REALTIME = 0 }
  if res = 0 then
  begin
    tp^.tv_sec  := ts.Sec;
    tp^.tv_usec := Int64(ts.Nsec) div 1000;
    Result := 0;
  end;
end;

end.
